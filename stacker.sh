#!/bin/bash

# 기본 경로
BASE_DIR="/data"

# Docker 설치 확인 및 설치 함수
check_and_install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker가 설치되어 있지 않습니다. 설치 중..."
        sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
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
    # Docker 설치 확인
    check_and_install_docker

    # Docker 데몬 실행 확인
    check_docker_daemon

    # Docker Compose 설치 확인
    check_and_install_docker_compose

    read -p "도메인 입력: " DOMAIN
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

    # Dockerfile 생성
    create_dockerfile "$DOMAIN" "$LANG" "$DB" "$USE_REDIS" "$USE_WEBSOCKET" "$WEBSOCKET_LANG"

    # Apache 설정 파일 생성
    create_apache_conf "$DOMAIN"

    # Docker Compose 파일 생성
    create_docker_compose "$DOMAIN" "$DB" "$USE_REDIS" "$USE_WEBSOCKET" "$WEBSOCKET_LANG"

    # Docker 서비스 시작
    docker-compose -f "$BASE_DIR/$DOMAIN/docker-compose.yml" up -d
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

    mkdir -p "$BASE_DIR/$DOMAIN"

    case $LANG in
        php)
            cat > "$BASE_DIR/$DOMAIN/Dockerfile" <<EOL
FROM php:8.3-apache
RUN docker-php-ext-install pdo pdo_mysql
COPY ./apache.conf /etc/apache2/sites-available/000-default.conf
COPY . /var/www/html/
RUN chown -R apache:apache /var/www/html
EOL
            if [ "$DB" == "sqlite3" ]; then
                echo "RUN docker-php-ext-install pdo_sqlite" >> "$BASE_DIR/$DOMAIN/Dockerfile"
            fi
            ;;
        python)
            cat > "$BASE_DIR/$DOMAIN/Dockerfile" <<EOL
FROM python:3.9
WORKDIR /app
COPY requirements.txt ./
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
EOL
            ;;
        nodejs)
            cat > "$BASE_DIR/$DOMAIN/Dockerfile" <<EOL
FROM node:16
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
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
COPY package*.json ./
RUN npm install
COPY . .
CMD ["node", "websocket.js"]
EOL
                ;;
            python)
                cat > "$BASE_DIR/$DOMAIN/websocket/Dockerfile" <<EOL
FROM python:3.9
WORKDIR /app
COPY requirements.txt ./
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "websocket.py"]
EOL
                ;;
            php)
                cat > "$BASE_DIR/$DOMAIN/websocket/Dockerfile" <<EOL
FROM php:8.3-cli
WORKDIR /app
COPY . .
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
    cat > "$BASE_DIR/$DOMAIN/apache.conf" <<EOL
<VirtualHost *:80>
    ServerName $DOMAIN
    ProxyPass / http://$DOMAIN:80/
    ProxyPassReverse / http://$DOMAIN:80/
</VirtualHost>
EOL
}

# Docker Compose 파일 생성
create_docker_compose() {
    DOMAIN=$1
    DB=$2
    USE_REDIS=$3
    USE_WEBSOCKET=$4
    WEBSOCKET_LANG=$5
    cat > "$BASE_DIR/$DOMAIN/docker-compose.yml" <<EOL
version: '3.8'
services:
  app:
    build: .
    container_name: ${DOMAIN}_container
    ports:
      - "80:80"
EOL

    if [ "$DB" == "mysql" ]; then
        cat >> "$BASE_DIR/$DOMAIN/docker-compose.yml" <<EOL
  db:
    image: mysql
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: ${DOMAIN}_db
    volumes:
      - $BASE_DIR/$DOMAIN/DB:/var/lib/mysql
EOL
    elif [ "$DB" == "postgresql" ]; then
        cat >> "$BASE_DIR/$DOMAIN/docker-compose.yml" <<EOL
  db:
    image: postgres
    environment:
      POSTGRES_USER: root
      POSTGRES_DB: ${DOMAIN}_db
    volumes:
      - $BASE_DIR/$DOMAIN/DB:/var/lib/postgresql/data
EOL
    elif [ "$DB" == "sqlite3" ]; then
        cat >> "$BASE_DIR/$DOMAIN/docker-compose.yml" <<EOL
  volumes:
    - $BASE_DIR/$DOMAIN/DB:/var/www/html/db
EOL
    fi

    if [ "$USE_REDIS" == "y" ]; then
        cat >> "$BASE_DIR/$DOMAIN/docker-compose.yml" <<EOL
  redis:
    image: redis
    ports:
      - "6379:6379"
EOL
    fi

    if [ "$USE_WEBSOCKET" == "y" ]; then
        cat >> "$BASE_DIR/$DOMAIN/docker-compose.yml" <<EOL
  websocket:
    build: ./websocket
    container_name: ${DOMAIN}_websocket
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
    docker-compose -f "$BASE_DIR/$DOMAIN/docker-compose.yml" ps

    echo "설치 상태 확인:"
    if [ -d "$BASE_DIR/$DOMAIN" ]; then
        echo "설치된 디렉토리: $BASE_DIR/$DOMAIN"
    else
        echo "설치되지 않음"
    fi

    echo "설정 파일 확인:"
    if [ -f "$BASE_DIR/$DOMAIN/apache.conf" ]; then
        echo "Apache 설정 파일 존재"
    else
        echo "Apache 설정 파일 없음"
    fi

    echo "로그 확인:"
    docker-compose -f "$BASE_DIR/$DOMAIN/docker-compose.yml" logs --tail=10
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
    *)
        echo "사용법: $0 {add|del|list|ssl [도메인]|ssl-fresh|check-status [도메인]}"
        ;;
esac