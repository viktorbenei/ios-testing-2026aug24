#!/usr/bin/env bash
#
# Analyze build timing to identify long-running tasks that aren't benefiting from cache
#
# Usage:
#   ./analyze-cache-effectiveness.sh build-results/build-timing.json
#

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <build-timing.json>"
    echo ""
    echo "Analyzes XCLogParser output to identify slow tasks that should be cached"
    exit 1
fi

TIMING_JSON="$1"

if [ ! -f "$TIMING_JSON" ]; then
    echo "Error: File not found: $TIMING_JSON"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    echo "Install with: brew install jq"
    exit 1
fi

echo "=================================================="
echo "Build Timing Analysis - Cache Effectiveness"
echo "=================================================="
echo ""

echo "📊 Top 15 Slowest Tasks:"
echo "------------------------"
jq -r '.. | objects | select(has("duration") and .duration > 0) |
  {duration, title, detailStepType, fetchedFromCache}' "$TIMING_JSON" | \
  jq -s 'sort_by(.duration) | reverse | .[:15] | .[] |
  if .fetchedFromCache then
    "\(.duration | tostring | .[0:6])s ✓ CACHED - \(.title)"
  else
    "\(.duration | tostring | .[0:6])s ✗ NOT CACHED - \(.title)"
  end'

echo ""
echo "🔨 Time by Task Type:"
echo "----------------------------"
jq -r '.. | objects | select(has("duration") and has("detailStepType") and .duration > 0) |
  {duration, detailStepType}' "$TIMING_JSON" | \
  jq -s 'group_by(.detailStepType) |
  map({type: .[0].detailStepType,
       count: length,
       total: (map(.duration) | add)}) |
  sort_by(.total) | reverse |
  .[] | "\(.total | tostring | .[0:6])s (\(.count) tasks) - \(.type)"'

echo ""
echo "⚡ Cache Hit Analysis:"
echo "---------------------"
TOTAL_CACHED=$(jq -r '.. | objects | select(has("fetchedFromCache") and .fetchedFromCache == true) | .duration' "$TIMING_JSON" | jq -s 'length')
TOTAL_NOT_CACHED=$(jq -r '.. | objects | select(has("fetchedFromCache") and .fetchedFromCache == false and .duration > 0) | .duration' "$TIMING_JSON" | jq -s 'length')

echo "Tasks fetched from cache: $TOTAL_CACHED"
echo "Tasks NOT from cache: $TOTAL_NOT_CACHED"

if [ "$TOTAL_CACHED" -gt 0 ]; then
  CACHED_TIME=$(jq -r '.. | objects | select(has("fetchedFromCache") and .fetchedFromCache == true and has("duration")) | .duration' "$TIMING_JSON" | jq -s 'add // 0')
  echo "Total time for cached tasks: ${CACHED_TIME}s"
fi

if [ "$TOTAL_NOT_CACHED" -gt 0 ]; then
  UNCACHED_TIME=$(jq -r '.. | objects | select(has("fetchedFromCache") and .fetchedFromCache == false and has("duration") and .duration > 0) | .duration' "$TIMING_JSON" | jq -s 'add // 0')
  echo "Total time for uncached tasks: ${UNCACHED_TIME}s"
fi

echo ""
echo "🐌 Long-Running Uncached Tasks (>1s):"
echo "---------------------------------------"
jq -r '.. | objects |
  select(has("duration") and has("fetchedFromCache") and
         .duration > 1 and .fetchedFromCache == false) |
  {duration, title, detailStepType}' "$TIMING_JSON" | \
  jq -s 'sort_by(.duration) | reverse | .[] |
  "\(.duration | tostring | .[0:6])s - \(.title) (\(.detailStepType))"' || echo "None found"

echo ""
echo "✨ Swift Caching Operations:"
echo "----------------------------"
jq -r '.. | objects | select(has("title") and (.title | contains("Swift caching"))) |
  {duration, title, fetchedFromCache}' "$TIMING_JSON" | \
  jq -s 'sort_by(.duration) | reverse | .[:10] | .[] |
  if .fetchedFromCache then
    "\(.duration | tostring | .[0:6])s ✓ - \(.title)"
  else
    "\(.duration | tostring | .[0:6])s ✗ - \(.title)"
  end' || echo "No Swift caching operations found"

echo ""
echo "💡 Recommendations:"
echo "------------------"
echo "1. Tasks marked '✗ NOT CACHED' are candidates for caching optimization"
echo "2. Compare long-running uncached tasks with your cache configuration"
echo "3. 'Swift caching materialize' operations show cache downloads - these should ideally be cached"
echo "4. Consider if SDK/platform dependencies can be cached to speed up 'Build stat cache' operations"
echo ""
echo "📁 View the HTML report for interactive exploration:"
echo "   open $(dirname "$TIMING_JSON")/build-timing.html"
echo ""
echo "📈 View timeline in Chrome for parallelization analysis:"
echo "   chrome://tracing and load $(dirname "$TIMING_JSON")/build-timing.json.gz"
