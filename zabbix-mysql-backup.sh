#!/bin/bash
######################################################################
#
# [�����T�v]
#  MySQL��zabbixDB��dump���ăo�b�N�A�b�v�f�B���N�g���ɓ]���B
#  dump��tar�ň��k���Adump���͍̂폜�B���k�t�@�C����3����c���B
#
# [����]
#  �Ȃ�
#
######################################################################
######################################################################
# �o�[�W���� �쐬�^�X�V�� �X�V��      �ύX���e
#---------------------------------------------------------------------
# 001-01     yu araki     YYYY/MM/DD  �V�K�쐬
######################################################################
######################################################################
# ���O����
######################################################################
#---------------------------------------------------------------------
# �ϐ���`
#---------------------------------------------------------------------
# �o�b�N�A�b�v�f�B���N�g��tgz�t�@�C�����J�E���g�p
BK_FILE_COUNT=0
# �폜����t�@�C���̐��J�E���g
DELETE_FILE_COUNT=0
# ���s���ʊi�[�t���O
RESULT_FLAG=0
# ���t
TODAY=`date "+%Y%m%d"`
# �^�C���X�^���v
NOW=`date "+%Y-%m-%d %H:%M:%S"`
# ���̃X�N���v�g�̃t�@�C����
SCRIPT_NAME=$(basename $0)
# ���̃X�N���v�g�̃t�@�C���p�X
SCRIPT_PATH="/usr/local/bin/ZABBIX_MYSQL_BACKUP/${SCRIPT_NAME}"
# �X�N���v�g���s�z�X�g��
HOST_NAME=$(hostname)
# �o�b�N�A�b�v�ێ�����(��)
readonly PERIOD=3
# ���[�J���o�b�N�A�b�v�i�[�f�B���N�g��
readonly BACKUP_DIR="/backup/mysql"
# �f�[�^�x�[�X�o�b�N�A�b�v�t�@�C����
readonly BACKUP_DATABASE_FILE="zabbix_mysql_dump_${TODAY}.sql"
# ���k��̃o�b�N�A�b�v�t�@�C����
readonly BACKUP_TAR_FILE="zabbix_mysql_backup_${TODAY}.tgz"
# �o�b�N�A�b�v���O�f�B���N�g��
readonly BK_LOG_DIR="/var/log/mysql_backup"
# �o�b�N�A�b�v���O�t�@�C����
readonly BACKUP_LOG="${BK_LOG_DIR}/zabbixdb_backup.log"
# �o�b�N�A�b�v�G���[���O�t�@�C����
readonly BACKUP_ERROR_LOG="${BK_LOG_DIR}/zabbixdb_backup_error.log"

## Zabbix DB�p�ϐ�
# DB���[�U��
readonly DB_USER="zabbix"
# DB��
readonly DB_NAME="zabbix"
# DB�p�X���[�h
readonly DB_PASSWD=$(openssl rsautl -decrypt -inkey ~/.ssh/mysql_rsa -in /usr/local/bin/ZABBIX_MYSQL_BACKUP/mysql_user_password.rsa)

## ���[�����M�p�ϐ�
# ���M���A�h���X
readonly FROM="zabbix-mysql-backup@monitor.com"
# ���M��A�h���X
readonly TO="���M��A�h���X���L��"
# ���[���^�C�g��
readonly SUBJECT="�yzabbix mysql db�zbackup_error "
######################################################################
# �֐���`
######################################################################
#---------------------------------------------------------------------
# �o�b�N�A�b�v���O�o��
#---------------------------------------------------------------------
function fnc_output_scriptlog() {
  (echo "$SCRIPT_NAME: $1 $NOW" >>$BACKUP_LOG) 2>/dev/null
  return $?
}

#---------------------------------------------------------------------
# �A���[�g���[�����M�֐�
#---------------------------------------------------------------------
function fnc_send_mail() {
  echo -e "$1 \nscript_path: $SCRIPT_PATH \nhostname: $HOST_NAME" | mail -s $SUBJECT -r $FROM $TO
  return $?
}

######################################################################
# �J�n����
######################################################################
# �J�n���O�o��
echo $TODAY start daily mysql backup process. >> $BACKUP_LOG

# �o�b�N�A�b�v�f�B���N�g�����݊m�F
mkdir -p $BACKUP_DIR

# �o�b�N�A�b�v���O�f�B���N�g�����݊m�F
mkdir -p $BK_LOG_DIR

######################################################################
# ���C������
######################################################################
#---------------------------------------------------------------------
# MySQL��ZabbixDB ���[�J���o�b�N�A�b�v
#---------------------------------------------------------------------
# �o�b�N�A�b�v�t�@�C�����݊m�F
FIND_FILE_COUNT=$(find $BACKUP_DIR -type f -name $BACKUP_TAR_FILE | wc -l)

# ������tgz�t�@�C�������݂��Ȃ��ꍇ
if [ $FIND_FILE_COUNT -eq 0 ]; then

    #MySQL���[�J���f�[�^�o�b�N�A�b�v
    MYSQL_PWD=$DB_PASSWD mysqldump --single-transaction --default-character-set=binary --flush-logs --events --quick -u${DB_USER} ${DB_NAME} >"${BACKUP_DIR}/${BACKUP_DATABASE_FILE}" 2>> $BACKUP_ERROR_LOG

    #���O�o��
    if [ "$?" = "0" ];then
        echo $NOW Mysql database backup completed. >> $BACKUP_LOG
        echo $NOW start compression of backup sql file backup. >> $BACKUP_LOG
    else
        # ���O�o�́A�G���[���[�����M
        for i in fnc_output_scriptlog fnc_send_mail ;do ${i} "Mysql database backup failed."; done
        # �G���[�t���O�w��
        RESULT_FLAG=1
    fi

    #�o�b�N�A�b�v�t�@�C�����k
    cd $BACKUP_DIR ; tar czvf ${BACKUP_TAR_FILE} ${BACKUP_DATABASE_FILE} 2>> $BACKUP_ERROR_LOG

    #���O�o��
    if [ "$?" = "0" ];then
        echo $NOW compression of backup sql is completed. delete the backup file before compression.  >> $BACKUP_LOG
        #���k�O�̃t�@�C���폜
        rm -f ${BACKUP_DIR}/${BACKUP_DATABASE_FILE} 2>> $BACKUP_ERROR_LOG
    else
        # ���O�o�́A�G���[���[�����M
        for i in fnc_output_scriptlog fnc_send_mail ;do ${i} "compression of backup sql is failed."; done
        #���k�O�̃t�@�C���폜
        rm -f ${BACKUP_DIR}/${BACKUP_DATABASE_FILE} 2>> $BACKUP_ERROR_LOG
        # �G���[�t���O�w��
        RESULT_FLAG=1
    fi

# ���ɓ�������tgz�t�@�C�������݂���ꍇ
else
    #���O�o��
    echo $NOW because today backup exists, skip backup process. >> $BACKUP_LOG
fi

#---------------------------------------------------------------------
# tgz�t�@�C����3�����葽�����݂���ꍇ�̏���
#---------------------------------------------------------------------
# �o�b�N�A�b�v�����m�F
if [ $RESULT_FLAG -eq 0 ]; then

    # �o�b�N�A�b�v�f�B���N�g����tgz�t�@�C���J�E���g
    BK_FILE_COUNT=$(ls -l $BACKUP_DIR/zabbix_mysql_backup_*.tgz | wc -l) 2>> $BACKUP_ERROR_LOG
    DELETE_FILE_COUNT=`expr $BK_FILE_COUNT - $PERIOD` 2>> $BACKUP_ERROR_LOG

    # 3�����葽�����݂���ꍇ
    if [ $DELETE_FILE_COUNT -gt 0 ]; then
        # tgz�t�@�C���폜
        cd $BACKUP_DIR ; rm -f $(ls -lt zabbix_mysql_backup_*.tgz | tail -${DELETE_FILE_COUNT} | awk '{ print $9;}') 2>> $BACKUP_ERROR_LOG
        # ���O�o��
        echo $NOW delete the three days before files from backup directory. >> $BACKUP_LOG
    else
        # ���O�o��
        echo $NOW there were no files of three days before in backup directory. >> $BACKUP_LOG
    fi

else
  # �o�b�N�A�b�v�������̏ꍇ�A�G���[�Ƃ��ďI��
  echo $TODAY zabbix mysql backup process has not finished. >> $BACKUP_LOG

  exit 1
fi

######################################################################
# �I������
######################################################################
#�I�����O�o��
echo $TODAY finished daily backup process. >> $BACKUP_LOG

exit 0