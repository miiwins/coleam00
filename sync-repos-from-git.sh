#!/bin/bash

# Script to check and sync all git repositories in subdirectories at https://github.com/dynamous-community
# Usage: ./sync-repos.sh [--check-only|--sync]

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
MODE="interactive"
if [ "$1" = "--check-only" ]; then
    MODE="check"
elif [ "$1" = "--sync" ]; then
    MODE="sync"
fi

# Store the base directory
BASE_DIR=$(pwd)

echo -e "${BLUE}=== Dynamous Repository Sync Tool ===${NC}\n"

# Arrays to store repo status
declare -a UP_TO_DATE=()
declare -a HAS_UPDATES=()
declare -a NO_UPSTREAM=()
declare -a NOT_GIT=()
declare -a CLONED=()

# Check for missing repositories from .gitmodules and clone them
GITMODULES_FILE="$BASE_DIR/.gitmodules"
if [ -f "$GITMODULES_FILE" ]; then
    echo -e "${BLUE}Checking for missing repositories from .gitmodules...${NC}\n"

    # Parse .gitmodules file
    current_path=""
    current_url=""

    while IFS= read -r line; do
        # Extract path
        if [[ $line =~ ^[[:space:]]*path[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            current_path="${BASH_REMATCH[1]}"
        fi

        # Extract url
        if [[ $line =~ ^[[:space:]]*url[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            current_url="${BASH_REMATCH[1]}"
        fi

        # When we have both path and url, check if repo exists
        if [ -n "$current_path" ] && [ -n "$current_url" ]; then
            if [ ! -d "$current_path" ]; then
                echo -e "${YELLOW}Repository missing: ${current_path}${NC}"
                echo -e "${BLUE}Cloning from ${current_url}...${NC}"

                if git clone "$current_url" "$current_path" 2>/dev/null; then
                    echo -e "${GREEN}✓ Successfully cloned ${current_path}${NC}\n"
                    CLONED+=("$current_path")
                else
                    echo -e "${RED}✗ Failed to clone ${current_path}${NC}\n"
                fi
            fi

            # Reset for next submodule
            current_path=""
            current_url=""
        fi
    done < "$GITMODULES_FILE"

    if [ ${#CLONED[@]} -gt 0 ]; then
        echo -e "${GREEN}Cloned ${#CLONED[@]} missing repository/repositories${NC}\n"
    else
        echo -e "${GREEN}All repositories from .gitmodules are present${NC}\n"
    fi
fi

# First pass: Check all repositories
echo -e "${BLUE}Scanning repositories...${NC}\n"

for dir in */; do
    # Skip if not a directory
    [ -d "$dir" ] || continue

    # Remove trailing slash
    repo_name="${dir%/}"

    # Check if it's a git repository
    if [ ! -d "$dir/.git" ]; then
        NOT_GIT+=("$repo_name")
        continue
    fi

    cd "$dir"

    # Fetch latest changes
    echo -e "${BLUE}Checking ${repo_name}...${NC}"
    git fetch origin --quiet 2>/dev/null || {
        echo -e "${RED}✗ Failed to fetch${NC}"
        cd "$BASE_DIR"
        continue
    }

    # Get local and remote commit hashes
    LOCAL=$(git rev-parse @ 2>/dev/null)
    REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "no-upstream")

    if [ "$REMOTE" = "no-upstream" ]; then
        NO_UPSTREAM+=("$repo_name")
        echo -e "${YELLOW}⚠ No upstream branch configured${NC}"
    elif [ "$LOCAL" = "$REMOTE" ]; then
        UP_TO_DATE+=("$repo_name")
        echo -e "${GREEN}✓ Up to date${NC}"
    else
        # Count commits behind
        BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "?")
        HAS_UPDATES+=("$repo_name:$BEHIND")
        echo -e "${YELLOW}⚠ ${BEHIND} commit(s) behind${NC}"
    fi

    cd "$BASE_DIR"
    echo ""
done

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
if [ ${#CLONED[@]} -gt 0 ]; then
    echo -e "${GREEN}✓ Cloned: ${#CLONED[@]}${NC}"
fi
echo -e "${GREEN}✓ Up to date: ${#UP_TO_DATE[@]}${NC}"
echo -e "${YELLOW}⚠ Updates available: ${#HAS_UPDATES[@]}${NC}"
echo -e "${RED}⚠ No upstream: ${#NO_UPSTREAM[@]}${NC}"
echo -e "Not git repos: ${#NOT_GIT[@]}\n"

# Show repos with updates
if [ ${#HAS_UPDATES[@]} -gt 0 ]; then
    echo -e "${YELLOW}Repositories with updates:${NC}"
    for item in "${HAS_UPDATES[@]}"; do
        repo="${item%:*}"
        count="${item#*:}"
        echo -e "  • ${repo} (${count} commits behind)"
    done
    echo ""
fi

# Exit if check-only mode
if [ "$MODE" = "check" ]; then
    echo -e "${BLUE}Check complete. Use --sync to pull updates.${NC}"
    exit 0
fi

# Ask user if they want to sync (interactive mode)
if [ "$MODE" = "interactive" ] && [ ${#HAS_UPDATES[@]} -gt 0 ]; then
    read -p "Pull updates for all repositories? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Sync cancelled."
        exit 0
    fi
    MODE="sync"
fi

# Sync repositories if needed
if [ "$MODE" = "sync" ] && [ ${#HAS_UPDATES[@]} -gt 0 ]; then
    echo -e "${BLUE}=== Syncing repositories ===${NC}\n"

    for item in "${HAS_UPDATES[@]}"; do
        repo="${item%:*}"

        echo -e "${BLUE}Pulling ${repo}...${NC}"
        cd "$repo"

        if git pull --ff-only; then
            echo -e "${GREEN}✓ Successfully updated ${repo}${NC}\n"
        else
            echo -e "${RED}✗ Failed to update ${repo}${NC}\n"
        fi

        cd "$BASE_DIR"
    done

    echo -e "${GREEN}=== Sync complete! ===${NC}"
elif [ ${#HAS_UPDATES[@]} -eq 0 ]; then
    echo -e "${GREEN}All repositories are up to date!${NC}"
fi
