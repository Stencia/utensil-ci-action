#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import re
import shlex
import sys


DENY_REASON = (
    "PR merges and auto-merge are blocked by the project Codex hook. "
    "Stop after reporting PR readiness unless the user explicitly asks to merge this specific PR."
)
GH_GLOBAL_OPTIONS_WITH_VALUES = {
    "-R",
    "--repo",
    "--hostname",
    "--config",
    "--git-protocol",
}
SHELLS = {"bash", "sh", "zsh"}
SHELL_SEPARATORS = {"&&", "||", ";", "|"}
PULLS_MERGE_PATH = re.compile(r"(^|/)(pulls|pullRequests)/[0-9]+/merge($|[/?#])")
GRAPHQL_MERGE_MUTATIONS = (
    "enablePullRequestAutoMerge",
    "mergePullRequest",
)


def main() -> int:
    payload = json.load(sys.stdin)
    command = extract_command(payload)
    if not command:
        return 0

    blocked_reason = blocked_merge_reason(command)
    if blocked_reason is None:
        return 0

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": f"{DENY_REASON} Blocked pattern: {blocked_reason}.",
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


def blocked_merge_reason(command: str, depth: int = 0) -> str | None:
    if depth > 3:
        return None

    tokens = split_tokens(command)
    for segment in command_segments(tokens):
        if merge_override_enabled(segment):
            continue
        if segment_contains_graphql_merge(segment):
            return "GitHub GraphQL pull request merge mutation"

        for index, token in enumerate(segment):
            if os.path.basename(token) == "gh":
                reason = blocked_gh_reason(segment, index)
                if reason is not None:
                    return reason

    for inner_command in shell_inner_commands(tokens):
        reason = blocked_merge_reason(inner_command, depth + 1)
        if reason is not None:
            return reason

    return None


def split_tokens(command: str) -> list[str]:
    try:
        return shlex.split(command, posix=True)
    except ValueError:
        return command.split()


def command_segments(tokens: list[str]) -> list[list[str]]:
    segments: list[list[str]] = []
    segment: list[str] = []
    for token in tokens:
        if token in SHELL_SEPARATORS:
            if segment:
                segments.append(segment)
                segment = []
            continue
        segment.append(token)
    if segment:
        segments.append(segment)
    return segments


def merge_override_enabled(tokens: list[str]) -> bool:
    index = 0
    if index < len(tokens) and os.path.basename(tokens[index]) == "env":
        index += 1
        while index < len(tokens) and tokens[index].startswith("-"):
            index += 1

    while index < len(tokens):
        token = tokens[index]
        if token == "CODEX_ALLOW_PR_MERGE=1":
            return True
        if is_env_assignment(token):
            index += 1
            continue
        return False

    return False


def is_env_assignment(token: str) -> bool:
    name, separator, _value = token.partition("=")
    return bool(separator) and bool(name) and name.replace("_", "").isalnum() and not name[0].isdigit()


def blocked_gh_reason(tokens: list[str], gh_index: int) -> str | None:
    subcommand, subcommand_index = first_gh_subcommand(tokens, gh_index + 1)
    if subcommand is None:
        return None

    if subcommand == "pr" and has_pr_merge(tokens, subcommand_index + 1):
        return "gh pr merge"

    if subcommand == "api":
        rest = tokens[subcommand_index + 1:]
        if any(PULLS_MERGE_PATH.search(token) for token in rest):
            return "gh api pull request merge endpoint"
        if any(mutation in token for mutation in GRAPHQL_MERGE_MUTATIONS for token in rest):
            return "gh api GraphQL pull request merge mutation"

    return None


def first_gh_subcommand(tokens: list[str], index: int) -> tuple[str | None, int]:
    while index < len(tokens):
        token = tokens[index]
        if token in GH_GLOBAL_OPTIONS_WITH_VALUES:
            index += 2
            continue
        if any(token.startswith(f"{option}=") for option in GH_GLOBAL_OPTIONS_WITH_VALUES if option.startswith("--")):
            index += 1
            continue
        if token.startswith("-R") and token != "-R":
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        return token, index
    return None, index


def has_pr_merge(tokens: list[str], index: int) -> bool:
    while index < len(tokens):
        token = tokens[index]
        if token == "merge":
            return True
        if token.startswith("-"):
            index += 2 if token in GH_GLOBAL_OPTIONS_WITH_VALUES else 1
            continue
        return False
    return False


def segment_contains_graphql_merge(tokens: list[str]) -> bool:
    return any(mutation in token for mutation in GRAPHQL_MERGE_MUTATIONS for token in tokens)


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


if __name__ == "__main__":
    raise SystemExit(main())
