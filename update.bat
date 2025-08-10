@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem --- Tạo thư mục backups nếu chưa có ---
if not exist backups (
    mkdir backups
)

echo ===== Chạy backup trong container erpnext_production-backend-1 =====
docker exec erpnext_production-backend-1 bench --site frontend backup

echo ===== Copy file backup ra thư mục backups trên host =====
rem Copy toàn bộ file trong thư mục backup frontend
docker cp erpnext_production-backend-1:/home/frappe/frappe-bench/sites/frontend/private/backups/. backups\

echo ===== Dừng và xóa container, network, giữ volume =====
docker compose -f pwd_production.yml down

echo ===== Xóa image tahp:latest =====
docker rmi tahp:latest

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

echo ===== Chạy migrate cho site frontend =====
docker exec erpnext_production-backend-1 bench --site frontend migrate

endlocal
