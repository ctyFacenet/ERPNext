@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem --- Kiểm tra container backend có đang chạy không ---
docker ps -q -f name=erpnext_production-backend-1 > temp.txt
set /p BACKEND_RUNNING=<temp.txt
del temp.txt

rem --- Tạo thư mục backups nếu chưa có ---
if not exist backups (
    mkdir backups
)

if defined BACKEND_RUNNING (
    echo ===== Chạy backup trong container erpnext_production-backend-1 =====
    docker exec erpnext_production-backend-1 bench --site frontend backup

    echo ===== Copy file backup ra thư mục backups trên host =====
    rem Copy toàn bộ file trong thư mục backup frontend
    docker cp erpnext_production-backend-1:/home/frappe/frappe-bench/sites/frontend/private/backups/. backups\

    echo ===== Xóa file backup trong container để tránh tích tụ =====
    docker exec erpnext_production-backend-1 bash -c "rm -rf /home/frappe/frappe-bench/sites/frontend/private/backups/*"

    echo ===== Xóa cache, file tạm không cần thiết trong container =====
    docker exec erpnext_production-backend-1 bash -c "bench --site frontend clear-cache"
    docker exec erpnext_production-backend-1 bash -c "bench --site frontend clear-website-cache"
    docker exec erpnext_production-backend-1 bash -c "rm -rf /home/frappe/frappe-bench/sites/frontend/public/files/.cache"
)

echo ===== Dừng và xóa container, network, giữ volume =====
docker compose -f pwd_production.yml down
docker network prune -f
docker builder prune --filter "dangling=true" -f

if defined BACKEND_RUNNING (
echo ===== Xóa image tahp:latest =====
docker rmi tahp:latest
)

echo ===== Xóa các Docker volumes không dùng (ngoại trừ vscode*, erpnext*) =====
for /f "tokens=*" %%v in ('docker volume ls -q') do (
    set "volume=%%v"

    rem Bỏ qua volume bắt đầu bằng vscode hoặc erpnext
    echo !volume! | findstr /b /r /c:"vscode" /c:"erpnext" >nul
    if errorlevel 1 (
        rem Kiểm tra volume có đang dùng bởi container nào không
        set "usedBy="
        for /f "tokens=*" %%c in ('docker ps -q') do (
            for /f "tokens=*" %%m in ('docker inspect -f "{{range .Mounts}}{{if eq .Type \"volume\"}}{{.Name}}{{end}}{{end}}" %%c') do (
                if "%%m"=="!volume!" (
                    for /f "tokens=*" %%n in ('docker inspect -f "{{.Name}}" %%c') do (
                        set "usedBy=%%n"
                    )
                )
            )
        )

        if defined usedBy (
            echo Volume !volume! is used by container !usedBy!, giữ lại.
        ) else (
            echo Volume !volume! không được dùng, sẽ xóa.
            docker volume rm !volume!
        )
    )
)

echo ===== Build image mới (với timestamp) =====
powershell -Command "docker build --build-arg REBUILD_TS=$(Get-Date -Format 'yyyyMMddHHmmss') -t tahp:latest -f images/layered/Containerfile ."

echo ===== Khởi động lại docker compose =====
docker compose -f pwd_production.yml up -d --force-recreate

echo ===== Xóa các image không dùng =====
docker image prune -f

if defined BACKEND_RUNNING (
    docker exec erpnext_production-backend-1 bench --site frontend migrate
)