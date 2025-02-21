#!/bin/bash
: <<'stacker'
sudo firewall-cmd --list-all
sudo firewall-cmd --permanent --add-port=22/tcp
sudo firewall-cmd --reload
sudo vi /etc/ssh/sshd_config
>> PermitRootLogin yes
sudo systemctl restart sshd

wget https://raw.githubusercontent.com/Bae-Jeff/slacker/master/stacker.sh
mv stacker.sh /usr/local/bin/vov
sudo chmod +x /usr/local/bin/vov
#echo 'export PATH=$PATH:/path/to/your/script' >> ~/.bashrc
source ~/.bashrc

// podman + docker

sudo dnf install podman -y
sudo dnf install python3-pip -y
pip3 install podman-compose
sudo dnf install docker -y
sudo touch /etc/containers/nodocker
sudo systemctl start docker
sudo systemctl enable docker

// end podman + docker

sudo dnf install httpd -y
sudo systemctl enable httpd
sudo systemctl start httpd
sudo dnf install mod_ssl -y
sudo systemctl restart httpd

sudo firewall-cmd --permanent --add-port=21/tcp
sudo firewall-cmd --permanent --add-port=22/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=6379/tcp
sudo firewall-cmd --permanent --add-port=3000~3999/tcp
sudo firewall-cmd --permanent --add-port=5000~5999/tcp
sudo firewall-cmd --permanent --add-port=8000~8999/tcp
sudo firewall-cmd --reload
stacker

# 기본 경로
BASE_DIR="/data"

# Podman 설치 확인 및 설치 함수
check_and_install_podman() {
    if ! command -v podman &> /dev/null; then
        echo "Podman이 설치되어 있지 않습니다. 설치 중..."
        sudo dnf install -y podman
        echo "Podman이 설치되었습니다."
    else
        echo "Podman이 이미 설치되어 있습니다."
    fi
}

# Podman Compose 설치 확인 및 설치 함수
check_and_install_podman_compose() {
    if ! command -v pip3 &> /dev/null; then
        echo "pip3가 설치되어 있지 않습니다. 설치 중..."
        sudo dnf install -y python3-pip
    fi

    if ! command -v podman-compose &> /dev/null; then
        echo "Podman Compose가 설치되어 있지 않습니다. 설치 중..."
        pip3 install --user podman-compose
        echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
        source ~/.bashrc
        echo "Podman Compose가 설치되었습니다."
    else
        echo "Podman Compose가 이미 설치되어 있습니다."
    fi
}

# Docker 설치 확인 및 설치 함수
check_and_install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker가 설치되어 있지 않습니다. 설치 중..."
        sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
        sudo systemctl start docker
        sudo systemctl enable docker
        echo "Docker가 설치되었습니다."
    else
        echo "Docker가 이미 설치되어 있습니다."
    fi
}

# Docker Compose 설치 확인 및 설치 함수
check_and_install_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose가 설치되어 있지 않습니다. 설치 중..."
        sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo "Docker Compose가 설치되었습니다."
    else
        echo "Docker Compose가 이미 설치되어 있습니다."
    fi
}

# Docker 데몬 실행 확인 함수
check_docker_daemon() {
    if ! systemctl is-active --quiet docker; then
        echo "Docker 데몬이 실행되고 있지 않습니다. Docker 데몬을 시작합니다..."
        sudo systemctl start docker
        if ! systemctl is-active --quiet docker; then
            echo "Docker 데몬을 시작할 수 없습니다. 수동으로 Docker를 시작하세요."
            exit 1
        fi
    else
        echo "Docker 데몬이 실행 중입니다."
    fi
}

# 사이트 추가 함수
add_site() {
    read -p "도메인 입력: " DOMAIN

    # 도메인 디렉토리 존재 여부 확인
    if [ -d "$BASE_DIR/$DOMAIN" ]; then
        echo "도메인이 이미 존재합니다: $DOMAIN"
        return
    fi

    # Podman 설치 확인
    check_and_install_podman

    # Podman Compose 설치 확인
    check_and_install_podman_compose

    echo "언어 선택 (php, python, nodejs): "
    select LANG in "php" "python" "nodejs"; do break; done
    echo "DB 선택 (mysql, postgresql, sqlite3): "
    select DB in "mysql" "postgresql" "sqlite3"; do break; done
    read -p "Redis 사용 여부 (y/n): " USE_REDIS
    read -p "웹소켓 서버 추가 여부 (y/n): " USE_WEBSOCKET

    if [ "$USE_WEBSOCKET" == "y" ]; then
        echo "웹소켓 서버 언어 선택 (nodejs, python, php): "
        select WEBSOCKET_LANG in "nodejs" "python" "php"; do break; done
    fi
    
    # Apache 설정 파일 생성
    create_apache_conf "$DOMAIN"

    # Dockerfile 생성
    create_dockerfile "$DOMAIN" "$LANG" "$DB" "$USE_REDIS" "$USE_WEBSOCKET" "$WEBSOCKET_LANG"

    # Podman Compose 파일 생성
    create_docker_compose "$DOMAIN" "$DB" "$USE_REDIS" "$USE_WEBSOCKET" "$WEBSOCKET_LANG"

    # Podman 서비스 시작
    podman-compose -f "$BASE_DIR/$DOMAIN/docker-compose.yml" up -d
    echo "사이트가 추가되었습니다: $DOMAIN"
}

# Dockerfile 생성
create_dockerfile() {
    DOMAIN=$1
    LANG=$2
    DB=$3
    USE_REDIS=$4
    USE_WEBSOCKET=$5
    WEBSOCKET_LANG=$6 

    case $LANG in
        php)
            cat > "$BASE_DIR/$DOMAIN/Dockerfile" <<EOL
FROM php:8.3-apache

# 필요한 디렉토리 생성
RUN mkdir -p /var/www/html

# RUN apt-get update
# RUN apt-get install -y lynx
# apache2ctl status 이거 필요하면 위 에거 설치

# 필요한 PHP 확장 설치
RUN docker-php-ext-install pdo pdo_mysql
# Apache 설정 복사
# COPY apache.conf /etc/apache2/apache2.conf

RUN cat /etc/apache2/apache2.conf

# 애플리케이션 파일 복사
# COPY source /var/www/html/

# 권한 설정
RUN chown -R www-data:www-data /var/www/html

# Apache2 설정 활성화
RUN a2ensite 000-default && a2enmod rewrite

# Apache2 서비스 시작
CMD ["apache2-foreground"]
EOL
            if [ "$DB" == "sqlite3" ]; then
                echo "RUN docker-php-ext-install pdo_sqlite" >> "$BASE_DIR/$DOMAIN/Dockerfile"
            fi
            ;;
        python)
            cat > "$BASE_DIR/$DOMAIN/Dockerfile" <<EOL
FROM python:3.9
WORKDIR /app
COPY $BASE_DIR/$DOMAIN/requirements.txt ./
RUN pip install -r requirements.txt
COPY $BASE_DIR/$DOMAIN/. .
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
EOL
            ;;
        nodejs)
            cat > "$BASE_DIR/$DOMAIN/Dockerfile" <<EOL
FROM node:16
WORKDIR /app
COPY $BASE_DIR/$DOMAIN/package*.json ./
RUN npm install
COPY $BASE_DIR/$DOMAIN/. .
CMD ["npm", "start"]
EOL
            ;;
    esac

    # 웹소켓 서버 Dockerfile 생성
    if [ "$USE_WEBSOCKET" == "y" ]; then
        mkdir -p "$BASE_DIR/$DOMAIN/websocket"
        case $WEBSOCKET_LANG in
            nodejs)
                cat > "$BASE_DIR/$DOMAIN/websocket/Dockerfile" <<EOL
FROM node:16
WORKDIR /app
COPY $BASE_DIR/$DOMAIN/websocket/package*.json ./
RUN npm install
COPY $BASE_DIR/$DOMAIN/websocket/. .
CMD ["node", "websocket.js"]
EOL
                ;;
            python)
                cat > "$BASE_DIR/$DOMAIN/websocket/Dockerfile" <<EOL
FROM python:3.9
WORKDIR /app
COPY $BASE_DIR/$DOMAIN/websocket/requirements.txt ./
RUN pip install -r requirements.txt
COPY $BASE_DIR/$DOMAIN/websocket/. .
CMD ["python", "websocket.py"]
EOL
                ;;
            php)
                cat > "$BASE_DIR/$DOMAIN/websocket/Dockerfile" <<EOL
FROM php:8.3-cli
WORKDIR /app
COPY $BASE_DIR/$DOMAIN/websocket/. .
CMD ["php", "websocket.php"]
EOL
                ;;
        esac
    fi

    # Redis 설치 옵션
    if [ "$USE_REDIS" == "y" ]; then
        echo "Redis를 사용할 수 있도록 추가 설정 필요"
    fi
}

# Apache 설정 파일 생성
create_apache_conf() {
    DOMAIN=$1
    DOMAIN_TAG=$(echo "$DOMAIN" | sed 's/\./_/g')

    # 도메인 디렉토리 생성
    mkdir -p "$BASE_DIR/$DOMAIN"

    # 컨테이너 내부 Apache 설정 파일 생성
    cat > "$BASE_DIR/$DOMAIN/000-default.conf" <<EOL
<VirtualHost *:80>
    ServerAdmin webmaster@$DOMAIN
    DocumentRoot /var/www/html

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOL
    echo "Container Apache 설정 파일 생성됨: $BASE_DIR/$DOMAIN/000-default.conf"

    # 호스트의 Apache 설정 파일 생성
    cat > "/etc/httpd/conf.d/$DOMAIN.conf" <<EOL
<VirtualHost *:80>
    ServerName $DOMAIN
    ProxyPass / http://${DOMAIN_TAG}_app:80/
    ProxyPassReverse / http://${DOMAIN_TAG}_app:80/
</VirtualHost>
EOL
    echo "vHost Apache 설정 파일 생성됨: /etc/httpd/conf.d/$DOMAIN.conf"

    # SSL 설정 파일 생성
    cat > "/etc/httpd/conf.d/$DOMAIN.ssl.conf" <<EOL
<VirtualHost *:443>
    ServerName $DOMAIN
    ProxyPass / http://${DOMAIN_TAG}_app:80/
    ProxyPassReverse / http://${DOMAIN_TAG}_app:80/

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/$DOMAIN/chain.pem

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-ssl-access.log combined
</VirtualHost>
EOL
    echo "SSL Apache 설정 파일 생성됨: /etc/httpd/conf.d/$DOMAIN.ssl.conf"
}

# 기존 웹 서비스 컨테이너 수 계산
existing_web_containers=$(podman ps -a --format "{{.Names}}" | grep "_app" | wc -l)

# 기존 MySQL 컨테이너 수 계산
existing_mysql_containers=$(podman ps -a --format "{{.Names}}" | grep "_mysql" | wc -l)

# 기존 PostgreSQL 컨테이너 수 계산
existing_postgres_containers=$(podman ps -a --format "{{.Names}}" | grep "_postgres" | wc -l)

# 웹 서비스 포트 설정
web_port=$((8001 + existing_web_containers))

# MySQL 포트 설정
mysql_port=$((3001 + existing_mysql_containers))

# PostgreSQL 포트 설정
postgres_port=$((5001 + existing_postgres_containers))

# Docker Compose 파일 생성
create_docker_compose() {
    DOMAIN=$1
    DB=$2
    USE_REDIS=$3
    USE_WEBSOCKET=$4
    WEBSOCKET_LANG=$5

    DOMAIN_TAG=$(echo "$DOMAIN" | sed 's/\./_/g')

    cat > "$BASE_DIR/$DOMAIN/docker-compose.yml" <<EOL
version: '3.8'
services:
  app:
    build: .
    image: ${DOMAIN_TAG}:1.0.0
    container_name: ${DOMAIN_TAG}_app
    ports:
      - "${web_port}:80"
    volumes:
      - $BASE_DIR/$DOMAIN/configs/www:/var/www/html
EOL

    if [ "$DB" == "mysql" ]; then
        cat >> "$BASE_DIR/$DOMAIN/docker-compose.yml" <<EOL
  db:
    image: docker.io/library/mysql:5.7
    container_name: ${DOMAIN_TAG}_mysql
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: ${DOMAIN_TAG}_db
    ports:
      - "${mysql_port}:3306"
    volumes:
      - $BASE_DIR/$DOMAIN/database:/var/lib/mysql
EOL
    elif [ "$DB" == "postgresql" ]; then
        cat >> "$BASE_DIR/$DOMAIN/docker-compose.yml" <<EOL
  db:
    image: docker.io/library/postgres:13
    container_name: ${DOMAIN_TAG}_postgres
    environment:
      POSTGRES_USER: root
      POSTGRES_DB: ${DOMAIN_TAG}_db
    ports:
      - "${postgres_port}:5432"
    volumes:
      - $BASE_DIR/$DOMAIN/database:/var/lib/postgresql/data
EOL
    fi

    if [ "$USE_REDIS" == "y" ]; then
        cat >> "$BASE_DIR/$DOMAIN/docker-compose.yml" <<EOL
  redis:
    image: redis
    container_name: ${DOMAIN_TAG}_redis
    ports:
      - "6379:6379"
EOL
    fi

    if [ "$USE_WEBSOCKET" == "y" ]; then
        cat >> "$BASE_DIR/$DOMAIN/docker-compose.yml" <<EOL
  websocket:
    build: ./websocket
    container_name: ${DOMAIN_TAG}_websocket
    ports:
      - "8080:8080"
EOL
    fi
}

# 사이트 삭제 함수
delete_site() {
    read -p "삭제할 도메인 입력: " DOMAIN
    rm -rf "$BASE_DIR/$DOMAIN"
    echo "사이트가 삭제되었습니다: $DOMAIN"
}

# 리스트 함수
list_sites() {
    echo "현재 활성화된 사이트:"
    ls "$BASE_DIR"
}

# SSL 인증서 목록 표시
ssl_list() {
    echo "SSL 인증서 목록:"
    ls /etc/letsencrypt/live/
}

# SSL 인증서 갱신
ssl_fresh() {
    DOMAIN=$1

    if [ -z "$DOMAIN" ]; then
        read -p "전체 도메인의 SSL 인증서를 갱신하겠습니까? (y/n): " CONFIRM
        if [ "$CONFIRM" == "y" ]; then
            echo "전체 SSL 인증서 갱신 중..."
            sudo certbot renew
            echo "전체 SSL 인증서가 갱신되었습니다."
        else
            echo "갱신이 취소되었습니다."
        fi
    else
        read -p "$DOMAIN의 SSL 인증서를 갱신하시겠습니까? (y/n): " CONFIRM
        if [ "$CONFIRM" == "y" ]; then
            echo "SSL 인증서를 갱신 중: $DOMAIN"
            sudo certbot --apache -d "$DOMAIN"
            echo "$DOMAIN의 SSL 인증서가 갱신되었습니다."
        else
            echo "갱신이 취소되었습니다."
        fi
    fi
}

# SSL 체크 및 설치 함수
check_ssl() {
    DOMAIN=$1

    # Certbot 설치 확인
    if ! command -v certbot &> /dev/null; then
        echo "Certbot이 설치되어 있지 않습니다. 설치 중..."
        sudo dnf install certbot python3-certbot-apache -y
    fi

    # SSL 인증서 경로
    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"

    # SSL 인증서가 존재하는지 확인
    if [ -f "$CERT_PATH" ]; then
        echo "인증서가 이미 존재합니다: $DOMAIN"
        return
    fi

    read -p "$DOMAIN의 SSL 인증서를 발급하시겠습니까? (y/n): " CONFIRM
    if [ "$CONFIRM" == "y" ]; then
        # SSL 인증서 발급
        echo "SSL 인증서를 발급받고 있습니다: $DOMAIN"
        sudo certbot --apache -d "$DOMAIN"
    else
        echo "발급이 취소되었습니다."
    fi
}

# 상태 확인 함수
check_status() {
    DOMAIN=$1
    if [ -z "$DOMAIN" ]; then
        echo "도메인을 입력하세요."
        return
    fi

    echo "도메인 상태 확인 중: $DOMAIN"
    podman-compose -f "$BASE_DIR/$DOMAIN/docker-compose.yml" ps

    echo "설치 상태 확인:"
    if [ -d "$BASE_DIR/$DOMAIN" ]; then
        echo "설치된 디렉토리: $BASE_DIR/$DOMAIN"
    else
        echo "설치되지 않음"
    fi

    echo "설정 파일 확인:"
    if [ -f "$BASE_DIR/$DOMAIN/000-default.conf" ]; then
        echo "Container Apache 설정 파일 존재"
    else
        echo "Container Apache 설정 파일 없음"
    fi

    echo "로그 확인:"
    podman-compose -f "$BASE_DIR/$DOMAIN/docker-compose.yml" logs --tail=10
}

# 컨테이너 제어 함수
control_container() {
    ACTION=$1
    DOMAIN=$2

    if [ -z "$DOMAIN" ]; then
        echo "도메인을 입력하세요."
        return
    fi

    DOMAIN_TAG=$(echo "$DOMAIN" | sed 's/\./_/g')

    case $ACTION in
        start)
            echo "컨테이너 시작 중: $DOMAIN"
            if podman ps -a --format "{{.Names}}" | grep -q "${DOMAIN_TAG}_app"; then
                echo "기존 컨테이너 실행 중: $DOMAIN"
                podman start ${DOMAIN_TAG}_app
            else
                echo "새로운 컨테이너 생성 및 실행 중: $DOMAIN"
                podman-compose -f "$BASE_DIR/$DOMAIN/docker-compose.yml" up -d
            fi
            ;;
        stop)
            echo "컨테이너 중지 중: $DOMAIN"
            podman-compose -f "$BASE_DIR/$DOMAIN/docker-compose.yml" down
            ;;
        delete)
            echo "컨테이너 삭제 중: $DOMAIN"
            podman-compose -f "$BASE_DIR/$DOMAIN/docker-compose.yml" down
            rm -rf "$BASE_DIR/$DOMAIN"
            echo "사이트가 삭제되었습니다: $DOMAIN"
            ;;
        shell)
            echo "컨테이너 셸 접속 중: $DOMAIN"
            podman exec -it ${DOMAIN_TAG}_app bash
            ;;
        status)
            echo "컨테이너 상태 확인 중: $DOMAIN"
            if ! podman ps --format "{{.Names}}" | grep -q "${DOMAIN_TAG}_app"; then
                echo "컨테이너가 실행 중이 아닙니다. 시작합니다: $DOMAIN"
                podman start ${DOMAIN_TAG}_app
            else
                echo "컨테이너가 이미 실행 중입니다: $DOMAIN"
            fi
            ;;
        *)
            echo "사용법: $0 {start|stop|delete|shell|status} [도메인]"
            ;;
    esac
}

# 메인 함수
case $1 in
    add)
        add_site
        ;;
    del)
        delete_site
        ;;
    list)
        list_sites
        ;;
    ssl-list)
        ssl_list
        ;;
    ssl)
        if [ -z "$2" ]; then
            echo "사용법: $0 ssl [도메인]"
            exit 1
        fi
        check_ssl "$2"
        ;;
    ssl-fresh)
        ssl_fresh "$2"
        ;;
    check-status)
        check_status "$2"
        ;;
    start|stop|delete|shell|status)
        control_container $1 $2
        ;;
    *)
        echo "사용법: $0 {add|del|list|ssl [도메인]|ssl-fresh|check-status [도메인]|start|stop|delete|shell|status [도메인]}"
        ;;
esac