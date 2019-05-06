#!/usr/bin/ksh

# resynchroniser la réplication mysql (après un reboot par exemple)

# discretion du login password
# login=
# password=
. $HOME/secrets

tmpfile=$(basename ${0})
tmpfile=${tmpfile%%.*}
tmpfile=/tmp/${tmpfile}.txt

exec 3>&1

exec 1>$tmpfile
exec 2>&1

cat <<EOF
From: Cron Daemon<${USER}@$(hostname).$(dnsdomainname)>
To: root@$(dnsdomainname)
Subject: MySQL <${USER}@$(dnsdomainname)> $0
Content-Type: text/html; charset=iso-8859-15

<html>
<pre>
EOF

master=192.168.1.10
slave=192.168.1.12

# Attendre tant que les services mysql ne sont pas lancés

while (! sudo -u portainer docker ps | grep mysql-docker); do echo Service mysql-docker absent sur $master; sleep 20; done

while (! ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -q ${login}@${slave} bash -c "'/bin/systemctl status mysql.service | grep running'"); do echo Service mysql absent sur nuc-debian64; sleep 20; done


# SYNCHRO MASTER VERS SLAVE
echo "Sur ${master}: FLUSH TABLES WITH READ LOCK;SHOW MASTER STATUS;"
result=$(/usr/bin/mysql -h${master} -u${login}  -p${password} -ANe "FLUSH TABLES WITH READ LOCK;SHOW MASTER STATUS;")

master_log_file=$(echo $result | awk '{print $1}' | tr -d '[:space:]')
master_log_position=$(echo $result | awk '{print $2}' | tr -d '[:space:]')

echo "master_log_file : ${master_log_file}"
echo "master_log_position : ${master_log_position}"

# Affichage binary log du slave avant modif
echo Sur ${slave}: SHOW SLAVE STATUS; 
slave_log_file=$(/usr/bin/mysql -h${slave} -u${login}  -p${password} -e "SHOW SLAVE STATUS;" -E | grep "Master_Log_File" | cut -d: -f2 | tail -n1)
slave_log_position=$(/usr/bin/mysql -h${slave} -u${login}  -p${password} -e "SHOW SLAVE STATUS;" -E | grep "Read_Master_Log_Pos" | cut -d: -f2 | tail -n1)

echo "slave_log_file avant: ${slave_log_file}"
echo "slave_log_position avant: ${slave_log_position}"


echo Alignement du slave $slave sur le master $master

echo "Sur ${slave}: STOP SLAVE; CHANGE MASTER TO MASTER_HOST='${master}', MASTER_USER='\${login}', MASTER_PASSWORD='\${password}', MASTER_LOG_FILE='${master_log_file}', MASTER_LOG_POS=${master_log_position};START SLAVE;"

result=$(/usr/bin/mysql -h${slave} -u${login}  -p${password} -e "STOP SLAVE; CHANGE MASTER TO MASTER_HOST='${master}', MASTER_USER='${login}', MASTER_PASSWORD='${password}', MASTER_LOG_FILE='${master_log_file}', MASTER_LOG_POS=${master_log_position};START SLAVE;")

echo "Sur ${master}: UNLOCK TABLES;"
result=$(/usr/bin/mysql -h${master} -u${login}  -p${password} -e "UNLOCK TABLES;")

# Affichage binary log du slave apres modif

slave_log_file=$(/usr/bin/mysql -h${slave} -u${login}  -p${password} -e "SHOW SLAVE STATUS;" -E | grep "Master_Log_File" | cut -d: -f2 | tail -n1 | tr -d '[:space:]')
slave_log_position=$(/usr/bin/mysql -h${slave} -u${login}  -p${password} -e "SHOW SLAVE STATUS;" -E | grep "Read_Master_Log_Pos" | cut -d: -f2 | tail -n1 | tr -d '[:space:]')

echo "slave_log_file apres: ${slave_log_file}"
echo "slave_log_position apres: ${slave_log_position}"

echo ""

# ICI VALIDER LA SYNCHRO SI MEME LOG ET MEME POS
if [ "${master_log_file}" = "${slave_log_file}" ] && [ "${master_log_position}" = "${slave_log_position}" ]
	then
        echo '<font color=green>La synchro master vers slave est OK</font>'
	else
        echo '<font color=green>La synchro master vers slave est KO</font>'
	fi

echo ""

STEP=2
if [ "${STEP}" = "2" ]
	then
# SYNCHRO SLAVE VERS MASTER

echo le master est maintenant ${slave}

result=$(/usr/bin/mysql -h${slave} -u${login}  -p${password} -ANe "FLUSH TABLES WITH READ LOCK;SHOW MASTER STATUS;")
master_log_file=$(echo $result | awk '{print $1}' | tr -d '[:space:]')
master_log_position=$(echo $result | awk '{print $2}' | tr -d '[:space:]')

echo "master_log_file : ${master_log_file}"
echo "master_log_position : ${master_log_position}"

# Affichage binary log du slave avant modif
slave_log_file=$(/usr/bin/mysql -h${master} -u${login}  -p${password} -e "SHOW SLAVE STATUS;" -E | grep "Master_Log_File" | cut -d: -f2 | tail -n1)
slave_log_position=$(/usr/bin/mysql -h${master} -u${login}  -p${password} -e "SHOW SLAVE STATUS;" -E | grep "Read_Master_Log_Pos" | cut -d: -f2 | tail -n1)

echo "slave_log_file avant: ${slave_log_file}"
echo "slave_log_position avant: ${slave_log_position}"

echo Alignement du slave $master sur le master $slave
result=$(/usr/bin/mysql -h${master} -u${login}  -p${password} -e "STOP SLAVE; CHANGE MASTER TO MASTER_HOST='${slave}', MASTER_USER='${login}', MASTER_PASSWORD='${password}', MASTER_LOG_FILE='${master_log_file}', MASTER_LOG_POS=${master_log_position};START SLAVE;")

# en cas de desynchronisation non corrigeable
#result=$(/usr/bin/mysql -h${master} -u${login}  -p${password} -e "RESET SLAVE; CHANGE MASTER TO MASTER_HOST='${slave}', MASTER_USER='${login}', MASTER_PASSWORD='${password}', MASTER_LOG_FILE='${master_log_file}', MASTER_LOG_POS=${master_log_position};START SLAVE;")

result=$(/usr/bin/mysql -h${slave} -u${login}  -p${password} -e "UNLOCK TABLES;")

# Affichage binary log du slave apres modif
slave_log_file=$(/usr/bin/mysql -h${master} -u${login}  -p${password} -e "SHOW SLAVE STATUS;" -E | grep "Master_Log_File" | cut -d: -f2 | tail -n1 | tr -d '[:space:]')
slave_log_position=$(/usr/bin/mysql -h${master} -u${login}  -p${password} -e "SHOW SLAVE STATUS;" -E | grep "Read_Master_Log_Pos" | cut -d: -f2 | tail -n1 | tr -d '[:space:]')

echo "slave_log_file apres: ${slave_log_file}"
echo "slave_log_position apres: ${slave_log_position}"


echo ""
# ICI VALIDER LA SYNCHRO SI MEME LOG ET MEME POS
if [ "${master_log_file}" = "${slave_log_file}" ] && [ "${master_log_position}" = "${slave_log_position}" ]
        then
        echo '<font color=green>La synchro slave vers master est OK</font>'
        else
        echo '<font color=green>La synchro slave vers master est KO</font>'
        fi
echo ""

fi


exec 1>&3 3>&-


if [ -f $tmpfile ] 
	then
	cat $tmpfile | /usr/sbin/sendmail ${login}@$(dnsdomainname)
	rm -f $tmpfile
	fi



