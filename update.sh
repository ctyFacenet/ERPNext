#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Đổi locale để in Unicode tốt hơn nếu cần
export LANG=C.UTF-8

# --- Kiểm tra container backend có đang chạy không ---
BACKEND_RUNNING=$(docker ps -q -f name=erpnext_production-backend-1)

# --- Tạo thư mục backups nếu chưa có ---
mkdir -p backups

if [ -n "$BACKEND_RUNNING" ]; then
    echo "===== Chạy backup trong container erpnext_production-backend-1 ====="
    docker exec erpnext_production-backend-1 bench --site frontend backup

    echo "===== Copy file backup ra thư mục backups trên host ====="
    # Copy toàn bộ file trong thư mục backup frontend
    docker cp erpnext_production-backend-1:/home/frappe/frappe-bench/sites/frontend/private/backups/. backups/

    echo "===== Xóa file backup trong container để tránh tích tụ ====="
    docker exec erpnext_production-backend-1 bash -c "rm -rf /home/frappe/frappe-bench/sites/frontend/private/backups/*"

    echo "===== Xóa cache, file tạm không cần thiết trong container ====="
    docker exec erpnext_production-backend-1 bash -c "bench --site frontend clear-cache"
    docker exec erpnext_production-backend-1 bash -c "bench --site frontend clear-website-cache"
    docker exec erpnext_production-backend-1 bash -c "rm -rf /home/frappe/frappe-bench/sites/frontend/public/files/.cache"
fi

echo "===== Dừng và xóa container, network, giữ volume ====="
docker compose -f pwd_production.yml down
docker network prune -f
docker builder prune --filter "dangling=true" -f

if [ -n "$BACKEND_RUNNING" ]; then
    echo "===== Xóa image tahp:latest ====="
    docker rmi tahp:latest || true
fi

echo "===== Xóa các Docker volumes không dùng (ngoại trừ vscode*, erpnext*) ====="
for volume in $(docker volume ls -q); do
    # Bỏ qua volume bắt đầu bằng vscode hoặc erpnext
    if [[ "$volume" == vscode* ]] || [[ "$volume" == erpnext* ]]; then
        echo "Bỏ qua volume $volume"
        continue
    fi

    # Kiểm tra volume có đang được dùng bởi container nào không
    usedBy=""
    for container in $(docker ps -q); do
        mounts=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "$container")
        for mount in $mounts; do
            if [ "$mount" = "$volume" ]; then
                usedBy=$(docker inspect -f '{{.Name}}' "$container")
                break 2
            fi
        done
    done

    if [ -n "$usedBy" ]; then
        echo "Volume $volume is used by container $usedBy, giữ lại."
    else
        echo "Volume $volume không được dùng, sẽ xóa."
        docker volume rm "$volume"
    fi
done

echo "===== Build image mới (với timestamp) ====="
TS=$(date +%Y%m%d%H%M%S)
docker build --build-arg REBUILD_TS="$TS" -t tahp:latest -f images/layered/Containerfile .

echo "===== Khởi động lại docker compose ====="
docker compose -f pwd_production.yml up -d --force-recreate

echo "===== Xóa các image không dùng ====="
docker image prune -f

if [ -n "$BACKEND_RUNNING" ]; then
    docker exec erpnext_production-backend-1 bench --site frontend migrate
fi
