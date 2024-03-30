#!/bin/bash
# check-journal.sh: mackerel check plugin for journal log.
# NOTICE: this script is Proof of Concept stage.
#         Don't use this for your mission critical work.
# Copyright 2024 Kenshi Muto

function log() {
  # ログ出力
  if [ "$DEBUG" ]; then
    echo "check-journal: $1" >&2
  fi
}

function usage() {
  # ヘルプ
  cat >&2 <<EOF
Usage:
  check-journal.sh [OPTIONS] -- [journalctl-OPTIONS]

Application options:
  -p, --pattern=PAT          Pattern to search for.
  -E, --exclude=PAT          Pattern to exclude from matching.
  -w, --warning-over=        Trigger a warning if matched lines is
                             over a number
  -c, --critical-over=       Trigger a critical if matched lines is
                             over a number
  -r, --return               Return matched line
  -i, --icase                Run a case insensitive match
  -s, --state-dir=DIR        Dir to keep state files under
      --debug                Output debug log to STDERR

Help Options:
  -h, --help                 Show this help message

journalctl options:
  After inserting '--', you can specify the journalctl command option
  to narrow down the target journal. Here is an example.

  -M --machine=CONTAINER     Operate on local container
  -m --merge                 Show entries from all available journals
  -D --directory=PATH        Show journal files from directory
     --file=PATH             Show journal file
     --root=ROOT             Operate on files below a root directory
     --image=IMAGE           Operate on files in filesystem image
     --namespace=NAMESPACE   Show journal data from specified journal namespace
  -u --unit=UNIT             Show logs from the specified unit
     --user-unit=UNIT        Show logs from the specified user unit
  -t --identifier=STRING     Show entries with the specified syslog identifier
  -p --priority=RANGE        Show entries with the specified priority
     --facility=FACILITY...  Show entries with the specified facilities
  -k --dmesg                 Show kernel message log from the current boot
     --utc                   Express time in Coordinated Universal Time (UTC)
EOF
}

# 初期値
PATTERN=
EXCLUDE=
# WARNINGOVERとCRITICALOVERは適当設定
WARNINGOVER=0
CRITICALOVER=2
RETURNRESULT=
INSENSITIVECASE=
# STATEDIRは本当は "pluginutil.PluginWorkDir()/check-journal" になりそう
STATEDIR=.
DEBUG=

# 返答コード
RET_OK=0
RET_WARNING=1
RET_CRITICAL=2
RET_UNKNOWN=3

# チェックプラグイン相当のオプション解析
# GNU getoptを利用している
# --file, --search-in-directory, --file-pattern, --no-state, --warning-level, --critical-level, --missing, --check-firstはjournalのログには合わなそうなので対応させていない
OPTIONS=$(getopt -q -n $(basename $0) -o p:E:w:c:ris:h -l pattern:,exclude:,warning-over:,critical-over:,return,icase,state-dir:,debug,help -- "$@")
eval set -- "$OPTIONS"

while true; do
  case "$1" in
    '-p'|'--pattern')
      PATTERN=$2
      shift 2
      continue
    ;;
    '-E'|'--exclude')
      EXCLUDE=$2
      shift 2
      continue
    ;;
    '--warning-over')
      WARNINGOVER=$2
      shift 2
      continue
    ;;
    '--critical-over')
      CRITICALOVER=$2
      shift 2
      continue
    ;;
    '-r'|'--return')
      RETURNRESULT=true
      shift
      continue
    ;;
    '-i'|'--icase')
      INSENSITIVECASE=true
      shift
      continue
    ;;
    '-s'|'--state-dir')
      STATEDIR=$2
      shift 2
      continue
    ;;
    '--debug')
      DEBUG=true
      shift
      continue
    ;;
    '-h'|'--help')
      usage
      exit $RET_OK
    ;;
    '--')
      shift
      break
    ;;
    *)
      usage
      exit $RET_UNKNOWN
    ;;
  esac
done

if [ -z "$PATTERN" ]; then
  echo "-p, --pattern is required"
  exit $RET_UNKNOWN
fi

# オプションに応じた固有のstateファイル名を作るために引数をbase64化している
# 同じログに対して複数のプラグイン設定を持つことがあるため、一意性に検索正規表現パターンも含めている
# オプションを試行錯誤するたびにbase64値が変わることになるので、毎回ログが頭から解析されてしまうが、仕様としている
# オプションでインジェクションされ得るが、rootを取られている時点でゲームオーバーだろう…
# カーソルはジャーナルの最新位置を表し、
# s=db027be00f714d5dadd1dacbbfcae594;i=12b47d4;b=a2ce87f529a64c9db4530802c47bfd06;m=bca2491ffb;t=614dc48cac697;x=6b59eeb35f52d260
# のような結果が返る(表現の将来保証はなさそう)
# journalctlの機能確認:
# --grepはsystemd version 237からの追加
# --cursor-file=FILE は systemd version 242からの追加
#   もしかしてdistro(しかもターゲットにしたいもの)によってはダメかも…

JOURNALCMD=journalctl
ARGBASE64=$(echo "$PATTERN $*" | base64)
STATEFILE="${STATEDIR}/check-journal-${ARGBASE64}"
FORCEOPTS="--no-pager --cursor-file=${STATEFILE}"

# $*のまま使うとスペースが引数分割されて困るので、bashの配列を利用している
ARGS=("$@")

if [ ! -f "$STATEFILE" ]; then
  log "statefile ${STATEFILE} for '$*' is created."
fi

# journalctlのオプションはホワイトリストにするほうがいいのかもしれない
LINES=$($JOURNALCMD $FORCEOPTS "${ARGS[@]}")

# PoCだし、Linuxだけ考えることにしてGNU grep前提で検索
# journalctlのgrepオプションのほうが正直高機能。ただexcludeがない
CASEOPTION=
if [ "$INSENSITIVECASE" ]; then
  CASEOPTION="-i"
fi

# check-logでは PATTERN、EXCLUDE のANDがあるが、このPoCでは対応していない
# grepで内部エラーが出たときも処理していない。本来はUNKNOWNを返すところ
if [ "$EXCLUDE" ]; then
  RESULT=$(echo "$LINES" | egrep $CASEOPTION "$PATTERN" | egrep -v "$EXCLUDE")
else
  RESULT=$(echo "$LINES" | egrep $CASEOPTION "$PATTERN")
fi

if [ -z "$RESULT" ]; then
  log "no match"
  exit $RET_OK
fi

MATCHLINECOUNTS=$(echo "$RESULT" | wc -l)
log "match ${MATCHLINECOUNTS} lines"

if [[ "$MATCHLINECOUNTS" -gt "$CRITICALOVER" ]]; then
  if [ "$RETURNRESULT" ]; then
    echo "$RESULT"
  fi
  exit $RET_CRITICAL
fi
if [[ "$MATCHLINECOUNTS" -gt "$WARNINGOVER" ]]; then
  if [ "$RETURNRESULT" ]; then
    echo "$RESULT"
  fi
  exit $RET_WARNING
fi

exit $RET_OK
