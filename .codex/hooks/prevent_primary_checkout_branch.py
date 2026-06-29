#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from dataclasses import dataclass


DEFAULT_BRANCH = os.environ.get("UTENSIL_DEFAULT_BRANCH", "main")
DENY_REASON = (
    "Primary checkout branch changes are blocked by the project Codex hook. "
    "Keep the primary checkout on main and create a linked worktree for feature work."
)
SHELLS = {"bash", "sh", "zsh"}
GIT_GLOBAL_OPTIONS_WITH_VALUES = {
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--exec-path",
    "--super-prefix",
}
SWITCH_OPTIONS_WITH_VALUES = {
    "--conflict",
    "--orphan",
}
CHECKOUT_OPTIONS_WITH_VALUES = {
    "--conflict",
    "--pathspec-from-file",
}
SHELL_SEPARATORS = {"&&", "||", ";", "|"}


@dataclass
class GitInvocation:
    subcommand: str
    args: list[str]
    cwd: str


def main() -> int:
    payload = json.load(sys.stdin)
    command = extract_command(payload)
    if not command:
        return 0

    base_cwd = extract_cwd(payload)
    blocked_reason = blocked_primary_checkout_reason(command, base_cwd)
    if blocked_reason is None:
        return 0

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": f"{DENY_REASON} {blocked_reason}",
        }
    }))
    return 0


def extract_command(payload: dict) -> str:
    tool_input = payload.get("tool_input")
    if isinstance(tool_input, str):
        return tool_input
    if not isinstance(tool_input, dict):
        return ""
    for key in ("command", "cmd"):
        value = tool_input.get(key)
        if isinstance(value, str):
            return value
    return ""


def extract_cwd(payload: dict) -> str:
    tool_input = payload.get("tool_input")
    if isinstance(tool_input, dict):
        for key in ("workdir", "cwd"):
            value = tool_input.get(key)
            if isinstance(value, str) and value:
                return resolve_path(value, os.getcwd())
    return os.getcwd()


def blocked_primary_checkout_reason(command: str, base_cwd: str, depth: int = 0) -> str | None:
    if depth > 3:
        return None

    tokens = split_tokens(command)
    for invocation in git_invocations(tokens, base_cwd):
        reason = blocked_git_invocation_reason(invocation)
        if reason is not None:
            return reason

    for inner_command in shell_inner_commands(tokens):
        reason = blocked_primary_checkout_reason(inner_command, base_cwd, depth + 1)
        if reason is not None:
            return reason

    return None


def split_tokens(command: str) -> list[str]:
    try:
        return shlex.split(command, posix=True)
    except ValueError:
        return command.split()


def git_invocations(tokens: list[str], base_cwd: str) -> list[GitInvocation]:
    invocations: list[GitInvocation] = []
    cwd = base_cwd
    index = 0

    while index < len(tokens):
        token = tokens[index]
        if token == "cd" and index + 1 < len(tokens):
            target = tokens[index + 1]
            if not target.startswith("-"):
                cwd = resolve_path(target, cwd)
                index += 2
                continue

        if os.path.basename(token) != "git":
            index += 1
            continue

        invocation, next_index = parse_git_invocation(tokens, index, cwd)
        if invocation is not None:
            invocations.append(invocation)
        index = max(next_index, index + 1)

    return invocations


def parse_git_invocation(tokens: list[str], git_index: int, base_cwd: str) -> tuple[GitInvocation | None, int]:
    cwd = base_cwd
    index = git_index + 1

    while index < len(tokens):
        token = tokens[index]
        if token in SHELL_SEPARATORS:
            return None, index + 1
        if token == "-C":
            if index + 1 >= len(tokens):
                return None, index + 1
            cwd = resolve_path(tokens[index + 1], cwd)
            index += 2
            continue
        if token.startswith("-C") and token != "-C":
            cwd = resolve_path(token[2:], cwd)
            index += 1
            continue
        if token in GIT_GLOBAL_OPTIONS_WITH_VALUES:
            index += 2
            continue
        if any(token.startswith(f"{option}=") for option in GIT_GLOBAL_OPTIONS_WITH_VALUES if option.startswith("--")):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        return (
            GitInvocation(token, command_args(tokens[index + 1:]), cwd),
            next_command_index(tokens, index + 1),
        )

    return None, index


def next_command_index(tokens: list[str], index: int) -> int:
    while index < len(tokens):
        if tokens[index] in SHELL_SEPARATORS:
            return index + 1
        index += 1
    return index


def command_args(tokens: list[str]) -> list[str]:
    args: list[str] = []
    for token in tokens:
        if token in SHELL_SEPARATORS:
            break
        args.append(token)
    return args


def blocked_git_invocation_reason(invocation: GitInvocation) -> str | None:
    if invocation.subcommand not in {"switch", "checkout"}:
        return None

    repo = repo_context(invocation.cwd)
    if repo is None or repo["toplevel"] != repo["primary"]:
        return None

    target = branch_target(invocation.subcommand, invocation.args)
    if target == DEFAULT_BRANCH:
        return None

    if target is None:
        target_description = "an implicit or unknown target"
    else:
        target_description = f"'{target}'"
    return f"Blocked git {invocation.subcommand} to {target_description} in primary checkout {repo['primary']}."


def repo_context(cwd: str) -> dict[str, str] | None:
    toplevel = git_output(cwd, "rev-parse", "--show-toplevel")
    if not toplevel:
        return None
    toplevel = realpath(toplevel)
    primary = configured_primary_checkout(toplevel) or inferred_primary_checkout(toplevel)
    if not primary:
        return None
    return {"toplevel": toplevel, "primary": realpath(primary)}


def configured_primary_checkout(toplevel: str) -> str | None:
    configured = git_output(toplevel, "config", "--path", "--get", "utensil.primaryCheckout")
    if not configured:
        return None
    return resolve_path(configured, toplevel)


def inferred_primary_checkout(toplevel: str) -> str | None:
    output = git_output(toplevel, "worktree", "list", "--porcelain")
    if not output:
        return None
    for line in output.splitlines():
        if line.startswith("worktree "):
            return line.removeprefix("worktree ")
    return None


def branch_target(subcommand: str, args: list[str]) -> str | None:
    if subcommand == "switch":
        return switch_branch_target(args)
    return checkout_branch_target(args)


def switch_branch_target(args: list[str]) -> str | None:
    index = 0
    while index < len(args):
        token = args[index]
        if token == "--":
            index += 1
            continue
        if token in ("-c", "-C", "--create", "--force-create", "--orphan"):
            return args[index + 1] if index + 1 < len(args) else None
        if token.startswith("--create="):
            return token.split("=", 1)[1]
        if token.startswith("--force-create="):
            return token.split("=", 1)[1]
        if token.startswith("--orphan="):
            return token.split("=", 1)[1]
        if token in ("--detach", "-d"):
            return None
        if token in SWITCH_OPTIONS_WITH_VALUES:
            index += 2
            continue
        if any(token.startswith(f"{option}=") for option in SWITCH_OPTIONS_WITH_VALUES):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        return token
    return None


def checkout_branch_target(args: list[str]) -> str | None:
    if "--" in args:
        return DEFAULT_BRANCH

    index = 0
    while index < len(args):
        token = args[index]
        if token in ("-b", "-B", "--orphan"):
            return args[index + 1] if index + 1 < len(args) else None
        if token.startswith("--orphan="):
            return token.split("=", 1)[1]
        if token in ("--detach",):
            return None
        if token in CHECKOUT_OPTIONS_WITH_VALUES:
            index += 2
            continue
        if any(token.startswith(f"{option}=") for option in CHECKOUT_OPTIONS_WITH_VALUES):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        return token
    return None


def shell_inner_commands(tokens: list[str]) -> list[str]:
    commands: list[str] = []
    for index, token in enumerate(tokens):
        if os.path.basename(token) not in SHELLS:
            continue
        cursor = index + 1
        while cursor < len(tokens):
            option = tokens[cursor]
            if option in ("-c", "-lc", "-ic"):
                if cursor + 1 < len(tokens):
                    commands.append(tokens[cursor + 1])
                break
            cursor += 1
    return commands


def git_output(cwd: str, *args: str) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", cwd, *args],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except OSError:
        return ""
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def resolve_path(path: str, cwd: str) -> str:
    path = os.path.expanduser(path)
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    return realpath(path)


def realpath(path: str) -> str:
    return os.path.realpath(os.path.abspath(path))


if __name__ == "__main__":
    raise SystemExit(main())
