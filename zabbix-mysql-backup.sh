#!/bin/bash
######################################################################
#
# [処理概要]
#  MySQLのzabbixDBをdumpしてバックアップディレクトリに転送。
#  dumpをtarで圧縮し、dump自体は削除。圧縮ファイルは3世代残す。
#
# [引数]
#  なし
#
######################################################################
######################################################################
# バージョン 作成／更新者 更新日      変更内容
#---------------------------------------------------------------------
# 001-01     yu araki     YYYY/MM/DD  新規作成
######################################################################
######################################################################
# 事前処理
######################################################################
#---------------------------------------------------------------------
# 変数定義
#---------------------------------------------------------------------
# バックアップディレクトリtgzファイル数カウント用
BK_FILE_COUNT=0
# 削除するファイルの数カウント
DELETE_FILE_COUNT=0
# 実行結果格納フラグ
RESULT_FLAG=0
# 日付
TODAY=`date "+%Y%m%d"`
# タイムスタンプ
NOW=`date "+%Y-%m-%d %H:%M:%S"`
# このスクリプトのファイル名
SCRIPT_NAME=$(basename $0)
# このスクリプトのファイルパス
SCRIPT_PATH="/usr/local/bin/ZABBIX_MYSQL_BACKUP/${SCRIPT_NAME}"
# スクリプト実行ホスト名
HOST_NAME=$(hostname)
# バックアップ保持期間(日)
readonly PERIOD=3
# ローカルバックアップ格納ディレクトリ
readonly BACKUP_DIR="/backup/mysql"
# データベースバックアップファイル名
readonly BACKUP_DATABASE_FILE="zabbix_mysql_dump_${TODAY}.sql"
# 圧縮後のバックアップファイル名
readonly BACKUP_TAR_FILE="zabbix_mysql_backup_${TODAY}.tgz"
# バックアップログディレクトリ
readonly BK_LOG_DIR="/var/log/mysql_backup"
# バックアップログファイル名
readonly BACKUP_LOG="${BK_LOG_DIR}/zabbixdb_backup.log"
# バックアップエラーログファイル名
readonly BACKUP_ERROR_LOG="${BK_LOG_DIR}/zabbixdb_backup_error.log"

## Zabbix DB用変数
# DBユーザ名
readonly DB_USER="zabbix"
# DB名
readonly DB_NAME="zabbix"
# DBパスワード
readonly DB_PASSWD=$(openssl rsautl -decrypt -inkey ~/.ssh/mysql_rsa -in /usr/local/bin/ZABBIX_MYSQL_BACKUP/mysql_user_password.rsa)

## メール送信用変数
# 送信元アドレス
readonly FROM="zabbix-mysql-backup@monitor.com"
# 送信先アドレス
readonly TO="送信先アドレスを記載"
# メールタイトル
readonly SUBJECT="【zabbix mysql db】backup_error "
######################################################################
# 関数定義
######################################################################
#---------------------------------------------------------------------
# バックアップログ出力
#---------------------------------------------------------------------
function fnc_output_scriptlog() {
  (echo "$SCRIPT_NAME: $1 $NOW" >>$BACKUP_LOG) 2>/dev/null
  return $?
}

#---------------------------------------------------------------------
# アラートメール送信関数
#---------------------------------------------------------------------
function fnc_send_mail() {
  echo -e "$1 \nscript_path: $SCRIPT_PATH \nhostname: $HOST_NAME" | mail -s $SUBJECT -r $FROM $TO
  return $?
}

######################################################################
# 開始処理
######################################################################
# 開始ログ出力
echo $TODAY start daily mysql backup process. >> $BACKUP_LOG

# バックアップディレクトリ存在確認
mkdir -p $BACKUP_DIR

# バックアップログディレクトリ存在確認
mkdir -p $BK_LOG_DIR

######################################################################
# メイン処理
######################################################################
#---------------------------------------------------------------------
# MySQLのZabbixDB ローカルバックアップ
#---------------------------------------------------------------------
# バックアップファイル存在確認
FIND_FILE_COUNT=$(find $BACKUP_DIR -type f -name $BACKUP_TAR_FILE | wc -l)

# 当日分tgzファイルが存在しない場合
if [ $FIND_FILE_COUNT -eq 0 ]; then

    #MySQLローカルデータバックアップ
    MYSQL_PWD=$DB_PASSWD mysqldump --single-transaction --default-character-set=binary --flush-logs --events --quick -u${DB_USER} ${DB_NAME} >"${BACKUP_DIR}/${BACKUP_DATABASE_FILE}" 2>> $BACKUP_ERROR_LOG

    #ログ出力
    if [ "$?" = "0" ];then
        echo $NOW Mysql database backup completed. >> $BACKUP_LOG
        echo $NOW start compression of backup sql file backup. >> $BACKUP_LOG
    else
        # ログ出力、エラーメール送信
        for i in fnc_output_scriptlog fnc_send_mail ;do ${i} "Mysql database backup failed."; done
        # エラーフラグ指定
        RESULT_FLAG=1
    fi

    #バックアップファイル圧縮
    cd $BACKUP_DIR ; tar czvf ${BACKUP_TAR_FILE} ${BACKUP_DATABASE_FILE} 2>> $BACKUP_ERROR_LOG

    #ログ出力
    if [ "$?" = "0" ];then
        echo $NOW compression of backup sql is completed. delete the backup file before compression.  >> $BACKUP_LOG
        #圧縮前のファイル削除
        rm -f ${BACKUP_DIR}/${BACKUP_DATABASE_FILE} 2>> $BACKUP_ERROR_LOG
    else
        # ログ出力、エラーメール送信
        for i in fnc_output_scriptlog fnc_send_mail ;do ${i} "compression of backup sql is failed."; done
        #圧縮前のファイル削除
        rm -f ${BACKUP_DIR}/${BACKUP_DATABASE_FILE} 2>> $BACKUP_ERROR_LOG
        # エラーフラグ指定
        RESULT_FLAG=1
    fi

# 既に当日分のtgzファイルが存在する場合
else
    #ログ出力
    echo $NOW because today backup exists, skip backup process. >> $BACKUP_LOG
fi

#---------------------------------------------------------------------
# tgzファイルが3世代より多く存在する場合の処理
#---------------------------------------------------------------------
# バックアップ完了確認
if [ $RESULT_FLAG -eq 0 ]; then

    # バックアップディレクトリ内tgzファイルカウント
    BK_FILE_COUNT=$(ls -l $BACKUP_DIR/zabbix_mysql_backup_*.tgz | wc -l) 2>> $BACKUP_ERROR_LOG
    DELETE_FILE_COUNT=`expr $BK_FILE_COUNT - $PERIOD` 2>> $BACKUP_ERROR_LOG

    # 3世代より多く存在する場合
    if [ $DELETE_FILE_COUNT -gt 0 ]; then
        # tgzファイル削除
        cd $BACKUP_DIR ; rm -f $(ls -lt zabbix_mysql_backup_*.tgz | tail -${DELETE_FILE_COUNT} | awk '{ print $9;}') 2>> $BACKUP_ERROR_LOG
        # ログ出力
        echo $NOW delete the three days before files from backup directory. >> $BACKUP_LOG
    else
        # ログ出力
        echo $NOW there were no files of three days before in backup directory. >> $BACKUP_LOG
    fi

else
  # バックアップが未完の場合、エラーとして終了
  echo $TODAY zabbix mysql backup process has not finished. >> $BACKUP_LOG

  exit 1
fi

######################################################################
# 終了処理
######################################################################
#終了ログ出力
echo $TODAY finished daily backup process. >> $BACKUP_LOG

exit 0