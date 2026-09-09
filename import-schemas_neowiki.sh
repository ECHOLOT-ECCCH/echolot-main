#!/usr/bin/env bash
#
# Import NeoWiki schemas into a running NeoWiki dev instance.
# Handles BOTH file formats:
#   - clean schema JSON:            {"description":..., "propertyDefinitions":{...}}
#   - raw MediaWiki API dump:       {"batchcomplete":"","query":{"pages":{...}}}
#
# Prereq: NeoWiki running (`make dev`), Docker up, python3 available.
# Usage:  bash import-schemas.sh
#         NEOWIKI_PROJECT=my-project bash import-schemas.sh
#
set -uo pipefail
PROJECT="${NEOWIKI_PROJECT:-neowiki-neowiki}"
DIR="$(cd "$(dirname "$0")" && pwd)/schemas"

CID="$(docker ps --filter "name=${PROJECT}-mediawiki" --format '{{.ID}}' | head -1)"
if [ -z "${CID}" ]; then
  echo "ERROR: no running MediaWiki container for project '${PROJECT}'. Start NeoWiki (make dev) first."
  exit 1
fi
if [ ! -d "${DIR}" ]; then
  echo "ERROR: no 'schemas/' folder next to this script (looked in ${DIR})."
  exit 1
fi

echo "Importing $(ls "${DIR}"/*.json 2>/dev/null | wc -l | tr -d ' ') schemas into container ${CID} ..."
ok=0; fail=0
for f in "${DIR}"/*.json; do
  name="$(basename "${f}" .json)"
  # Normalize to plain schema JSON (unwrap API dumps); print nothing on unknown format.
  content="$(python3 -c "
import sys,json
d=json.load(open(sys.argv[1]))
if isinstance(d,dict) and 'propertyDefinitions' in d:
    sys.stdout.write(json.dumps(d,ensure_ascii=False))
elif isinstance(d,dict) and 'query' in d:
    pg=list(d['query']['pages'].values())[0]
    sys.stdout.write(pg['revisions'][0]['slots']['main']['*'])
" "${f}" 2>/dev/null)"
  if [ -z "${content}" ]; then
    printf '  %-32s SKIP (unrecognized format)\n' "Schema:${name}"; fail=$((fail+1)); continue
  fi
  out="$(printf '%s' "${content}" | docker exec -i "${CID}" \
          php maintenance/edit.php "Schema:${name}" \
          --user "Maintenance script" --summary "Import schema" 2>&1 | tail -1)"
  if echo "${out}" | grep -qiE 'done|no change|ignored'; then
    printf '  %-32s ok\n' "Schema:${name}"; ok=$((ok+1))
  else
    printf '  %-32s FAIL: %s\n' "Schema:${name}" "${out}"; fail=$((fail+1))
  fi
done
echo "Done. imported=${ok} failed=${fail}"
echo "Browse: http://localhost:8484/wiki/Special:Schemas"
