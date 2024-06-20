# shellcheck shell=bash
function install-mongodb(){

    echo "install mongodb "

     bash -c "curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/mongodb-server-7.0.gpg"

    cat <<-EOF >"/etc/apt/sources.list.d/mongodb-org-7.0.list"
    deb [ arch=amd64,arm64 signed-by=/etc/apt/trusted.gpg.d/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse
EOF
     sudo apt-get update
     apt-get  install -y mongodb-org

     mongod --dbpath /var/lib/mongodb --fork --logpath /var/log/mongodb.log
     sleep 5
     mongosh admin --eval 'db.createUser({user:"nts", pwd:"nts##", roles:[{role:"readWriteAnyDatabase", db:"admin"}]})'
     mongod --dbpath /var/lib/mongodb --shutdown
     printf 'security:\n  authorization: enabled\n' >> /etc/mongod.conf
    # fix mongodb service reated permition
     chown -R mongodb:mongodb /var/lib/mongodb
     chmod -R 755 /var/lib/mongodb
     chown -R mongodb:mongodb /var/log/mongodb.log
     chmod -R 755 /var/log/mongodb.log


    return 0
}
