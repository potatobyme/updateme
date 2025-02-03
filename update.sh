#!/bin/bash
# Auto Update Script for Pterodactyl Panel
# Ensure you have backed up your panel files and database before running this script.
# Adjust PANEL_PATH and WEB_USER according to your environment.

# Variables - adjust these as necessary:
PANEL_PATH="/var/www/pterodactyl"    # Path to your Pterodactyl Panel installation
WEB_USER="www-data"                  # Web server user (e.g., www-data, nginx, apache)
UPDATE_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"

# Function to exit if a command fails
function exit_on_error() {
    echo "Error: $1"
    exit 1
}

echo "Starting Pterodactyl Panel update process..."

# Change to the panel directory
cd "$PANEL_PATH" || exit_on_error "Panel directory not found: $PANEL_PATH"

# Put the panel into maintenance mode
echo "Entering maintenance mode..."
php artisan down || exit_on_error "Failed to enter maintenance mode."

# Download and extract the latest panel release from GitHub
echo "Downloading and extracting the latest update from GitHub..."
curl -L "$UPDATE_URL" | tar -xzv || exit_on_error "Failed to download or extract the update."

# Set correct permissions for cache and storage directories
echo "Setting permissions for storage and cache directories..."
chmod -R 755 storage/* bootstrap/cache || exit_on_error "Failed to set permissions."

# Update Composer dependencies (ensure composer is installed and in your PATH)
echo "Updating Composer dependencies..."
composer install --no-dev --optimize-autoloader || exit_on_error "Composer install failed."

# Clear compiled caches to ensure new templates and configurations are loaded
echo "Clearing application caches..."
php artisan view:clear || exit_on_error "Failed to clear view cache."
php artisan config:clear || exit_on_error "Failed to clear config cache."

# Run database migrations (and seed any new default eggs)
echo "Running database migrations..."
php artisan migrate --seed --force || exit_on_error "Database migrations failed."

# Set file ownership to the web server user (modify as needed for your setup)
echo "Setting file ownership to ${WEB_USER}..."
chown -R "$WEB_USER":"$WEB_USER" "$PANEL_PATH"/* || exit_on_error "Failed to set file ownership."

# Restart the queue worker to load the new code
echo "Restarting queue workers..."
php artisan queue:restart || exit_on_error "Failed to restart queue workers."

# Bring the panel out of maintenance mode
echo "Exiting maintenance mode..."
php artisan up || exit_on_error "Failed to exit maintenance mode."

echo "Pterodactyl Panel update completed successfully."
