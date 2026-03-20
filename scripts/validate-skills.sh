#!/usr/bin/env bash
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
PASSED=0
TOTAL=0
ERRORS=""

check() {
  TOTAL=$((TOTAL + 1))
  if [ -z "$2" ]; then
    echo "[PASS] $1"
    PASSED=$((PASSED + 1))
  else
    echo "[FAIL] $1"
    echo "$2" | while IFS= read -r line; do [ -n "$line" ] && echo "       $line"; done || true
  fi
}

echo "=== Unity Skills Validation ==="
echo ""

# a) SKILL.md line counts
ERRORS=""
for f in "$SKILLS_DIR"/*/SKILL.md; do
  lines=$(wc -l < "$f")
  name="${f#"$SKILLS_DIR"/}"
  if [[ "$name" == "unity/SKILL.md" ]]; then
    [ "$lines" -gt 400 ] && ERRORS+="$name: ${lines}L (max 400)"$'\n'
  else
    [ "$lines" -gt 200 ] && ERRORS+="$name: ${lines}L (max 200)"$'\n'
  fi
done
check "SKILL.md line limits" "$ERRORS"

# b) YAML frontmatter
ERRORS=""
for f in "$SKILLS_DIR"/*/SKILL.md; do
  head -1 "$f" | grep -q "^---" || ERRORS+="${f#"$SKILLS_DIR"/}"$'\n'
done
check "YAML frontmatter present" "$ERRORS"

# c) Required sections
SECTIONS=("Ce que fait" "Prerequis" "Demarrage rapide|Quick Start" "Arbre de decision" "Regles strictes" "Skills connexes" "Troubleshooting")
ERRORS=""
for f in "$SKILLS_DIR"/*/SKILL.md; do
  name="${f#"$SKILLS_DIR"/}"
  # unity/SKILL.md is a reference guide, not an execution skill — skip section check
  [[ "$name" == "unity/SKILL.md" ]] && continue
  for section in "${SECTIONS[@]}"; do
    grep -qiE "$section" "$f" || ERRORS+="$name missing: $section"$'\n'
  done
done
check "Required sections in SKILL.md" "$ERRORS"

# d) No deprecated Unity version references
ERRORS=$(grep -rn "Unity 202[0-3]" "$SKILLS_DIR" 2>/dev/null || true)
check "No deprecated Unity version references" "$ERRORS"

# e) Reference files line limits (unity/ reference gets 700L, others 400L)
ERRORS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  lines=$(wc -l < "$f")
  name="${f#"$SKILLS_DIR"/}"
  if [[ "$name" == unity/references/* ]]; then
    [ "$lines" -gt 700 ] && ERRORS+="$name: ${lines}L (max 700)"$'\n'
  else
    [ "$lines" -gt 400 ] && ERRORS+="$name: ${lines}L (max 400)"$'\n'
  fi
done < <(find "$SKILLS_DIR" -path "*/references/*.md" -type f)
check "Reference files line limits" "$ERRORS"

echo ""
echo "Summary: $PASSED/$TOTAL checks passed"
[ "$PASSED" -eq "$TOTAL" ] && exit 0 || exit 1
