# journalctlをラップする形でのjournalログチェックプラグインの概念実証実装

[systemd](https://systemd.io/)のjournalログを監視するための[mackerel-agent](https://mackerel.io/ja/docs/entry/howto/install-agent)チェックプラグインの概念実証実装です。実験的なものであり、本格的な利用には避けることをお勧めします。

journalのデータを操作するのは複雑かつ変動が激しそうなので、インタラクションを行う`journalctl`コマンドをラップする形でのシェルスクリプト実装としています。

## 使い方
コマンドラインヘルプを以下に示します。

```
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
```

アプリケーションオプションは[check-log](https://mackerel.io/ja/docs/entry/plugins/check-log)相当に合わせています（ここにないオプションはjournalだと意味がないと思われるので削っています）。

- check-logでは`--pattern`と`--exclude`を複数指定してAND設定できるのですが、今の実装では対応していません（シェルで雑にやっていて大変なだけなので、Go言語実装であればできるでしょう）。また、単純にegrepを呼び出しているだけです。
- `--state-dir`はcheck-logではプラグイン用フォルダの下に`check-log`サブフォルダを作ってそこに保持する、という仕掛けになっているのですが、今の実装では判断できないのでカレントに`check-journal-<base64エンコード文字列>`という状態ファイルを置きます。サブフォルダを自動で作成することもしません。

Unitなどで絞り込むには、アプリケーションオプションを指定したあとに`--`を入れ、さらに`journalctl`コマンドのオプションを連ねます。たとえばUnit名を指定するのはよくあることでしょう。

コマンドライン上で動くことを確認できたら、スクリプトを`/usr/local/bin`などに配置し、`mackerel-agent.conf`のプラグインとして定義します。

```
[plugin.checks.journal-sshhoge]
command = ["/usr/local/bin/check-journal.sh", "-s", "/var/tmp", "-p", "hoge|moge", "-E", "nothoge", "-i", "-r", "--", "--unit", "ssh.service"]
```

## 現在の制限
- PoCステージが終わったらいずれにせよ全然別の実装になります。
- 利用している`journalctl`コマンドの`--cursor-file=FILE`オプションは、systemd version 242で追加されたもののため、これよりも古いバージョンがインストールされている場合は動作しません。ただし、Amazon Linux 2023、Oracle Linux 9、Ubuntu 22、Debian 12ではいずれもこのオプションが存在するので、対応は不要と思われます。

## ライセンス

Apache License Version 2.0

[LICENSE](LICENSE)
