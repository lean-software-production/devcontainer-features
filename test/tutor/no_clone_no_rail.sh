#!/usr/bin/env bash
# Checks run in child shells, so their $-expressions are single-quoted on purpose;
# the test library exists only inside the scenario container.
# shellcheck disable=SC2016,SC1091
set -e
source dev-container-features-test-lib

# The bb Feature's default state directory is the remote user's ~/.bb.
export BB_SERVER_URL=http://127.0.0.1:48986 BB_HOST_DAEMON_PORT=48987 BB_DATA_DIR="$HOME/.bb"

check "plugin config has no factory" bash -c 'node -e "const c=require(\"/usr/local/etc/tutor/config.json\"); process.exit(c.course===\"/home/node/absent-course\" && !(\"factory\" in c) ? 0 : 1)"'
check "plugin config names the default state directory" bash -c 'node -e "const c=require(\"/usr/local/etc/tutor/config.json\"); process.exit(c.dataDir===process.env.HOME+\"/.bb\" ? 0 : 1)"'
check "an empty disablePlugins leaves every plugin on" bash -c 'bb plugin list --json | node -e "let s=\"\";process.stdin.on(\"data\",(d)=>(s+=d)).on(\"end\",()=>process.exit(JSON.parse(s).plugins.find((x)=>x.id===\"automations\").enabled ? 0 : 1))"'
check "an empty theme leaves BB's theme alone" bash -c 'bb theme show --json | grep -q "\"themeId\": \"default\""'
check "empty courseRepo never clones" bash -c 'test ! -e /home/node/absent-course'
check "tutor plugin is running from the default state directory" bash -c 'bb plugin list --json | node -e "let s=\"\";process.stdin.on(\"data\",(d)=>(s+=d)).on(\"end\",()=>{const p=JSON.parse(s).plugins.find((x)=>x.id===\"tutor\"); process.exit(p && p.status===\"running\" && p.rootDir.startsWith(process.env.HOME+\"/.bb/.tutor-feature/plugin-\") ? 0 : 1)})"'
check "missing course is not registered" bash -c 'test "$(bb project list --json | node -e "let s=\"\";process.stdin.on(\"data\",(d)=>(s+=d)).on(\"end\",()=>process.stdout.write(String(JSON.parse(s).length)))")" = 0'
check "selectRail false leaves the thread list alone" bash -c 'bb settings ui get sidebar.threadListProvider --json | grep -q "\"thread-list/thread-list\""'
check "bootstrap is a clean no-op" bash -c 'tutor-feature-bootstrap 2>&1 | grep -q "courseRepo is empty"'
reportResults
