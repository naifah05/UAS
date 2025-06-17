#!/bin/bash

echo "⚠️  This script will REMOVE all Docker containers, images, volumes, and networks."
echo -n "Are you sure you want to continue? (y/N): "
read confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "❌ Aborted."
  exit 1
fi

echo "🛑 Stopping and removing all containers..."
docker rm -f $(docker ps -aq) 2>/dev/null || echo "No containers to remove."

#echo "🧹 Removing all images..."
#docker rmi -f $(docker images -q) 2>/dev/null || echo "No images to remove."

echo "📦 Removing all volumes..."
docker volume rm -f $(docker volume ls -q) 2>/dev/null || echo "No volumes to remove."

echo "🌐 Removing all user-defined networks..."
docker network rm $(docker network ls | grep -v "bridge\|host\|none" | awk '{print $1}') 2>/dev/null || echo "No user-defined networks to remove."

echo "🧼 Running Docker system prune (just in case)..."
docker system prune -a --volumes -f

echo "✅ Docker environment fully cleaned."
