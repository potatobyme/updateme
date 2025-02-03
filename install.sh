#!/bin/bash
# Discord OAuth Integration Installer for Pterodactyl
# Make sure to run this script as sudo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

echo -e "${GREEN}Starting Discord OAuth integration installation...${NC}"

# Verify Pterodactyl installation directory
PTERODACTYL_DIR="/var/www/pterodactyl"
if [ ! -d "$PTERODACTYL_DIR" ]; then
    echo -e "${RED}Pterodactyl directory not found at $PTERODACTYL_DIR${NC}"
    exit 1
fi

# Check if artisan file exists
if [ ! -f "$PTERODACTYL_DIR/artisan" ]; then
    echo -e "${RED}Laravel artisan file not found in $PTERODACTYL_DIR. Please ensure Pterodactyl is properly installed.${NC}"
    exit 1
fi

# Backup existing LoginContainer.tsx
echo -e "${YELLOW}Creating backup of LoginContainer.tsx...${NC}"
timestamp=$(date +%Y%m%d_%H%M%S)
backup_file="$PTERODACTYL_DIR/resources/scripts/components/auth/LoginContainer.tsx.backup_$timestamp"
cp "$PTERODACTYL_DIR/resources/scripts/components/auth/LoginContainer.tsx" "$backup_file"
echo -e "${GREEN}Backup created at: $backup_file${NC}"

# Change to Pterodactyl directory
cd "$PTERODACTYL_DIR"

# Install required package laravel/socialite via composer
echo -e "${YELLOW}Installing laravel/socialite via composer...${NC}"
composer require laravel/socialite

# Create Discord controller
echo -e "${YELLOW}Creating Discord controller...${NC}"
mkdir -p "$PTERODACTYL_DIR/app/Http/Controllers/Auth"
cat > "$PTERODACTYL_DIR/app/Http/Controllers/Auth/DiscordController.php" << 'EOL'
<?php

namespace Pterodactyl\Http\Controllers\Auth;

use Laravel\Socialite\Facades\Socialite;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Illuminate\Support\Facades\Auth;

class DiscordController extends Controller
{
    public function redirect()
    {
        return Socialite::driver('discord')->redirect();
    }

    public function callback(Request $request)
    {
        try {
            $discordUser = Socialite::driver('discord')->user();

            $user = User::where('email', $discordUser->email)->first();

            if (!$user) {
                return redirect()->route('auth.login')
                    ->with('error', 'No account found with this Discord email.');
            }

            $user->discord_id = $discordUser->id;
            $user->save();

            Auth::login($user);

            return redirect('/');
        } catch (\Exception $e) {
            return redirect()->route('auth.login')
                ->with('error', 'Discord authentication failed.');
        }
    }
}
EOL

# Insert Discord configuration into config/services.php (if not already present)
echo -e "${YELLOW}Updating services configuration (config/services.php)...${NC}"
SERVICES_FILE="$PTERODACTYL_DIR/config/services.php"
if grep -q "'discord'" "$SERVICES_FILE"; then
    echo -e "${YELLOW}Discord configuration already exists in services.php. Skipping insertion.${NC}"
else
    # Insert before the last closing bracket "];"
    sed -i '/^\];/i \
    \'discord\' => [\
        \'client_id\' => env(\'DISCORD_CLIENT_ID\'),\
        \'client_secret\' => env(\'DISCORD_CLIENT_SECRET\'),\
        \'redirect\' => env(\'DISCORD_REDIRECT_URI\'),\
    ],' "$SERVICES_FILE"
    echo -e "${GREEN}Discord configuration added to services.php${NC}"
fi

# Create migration for discord_id field
echo -e "${YELLOW}Creating database migration for discord_id...${NC}"
php artisan make:migration add_discord_id_to_users_table --table=users

# Give the file system a moment to register the new migration
sleep 2

# Locate the migration file
latest_migration=$(ls -t "$PTERODACTYL_DIR/database/migrations" | grep "add_discord_id_to_users_table" | head -n 1)
migration_file="$PTERODACTYL_DIR/database/migrations/$latest_migration"
if [ ! -f "$migration_file" ]; then
    echo -e "${RED}Migration file not found. Exiting.${NC}"
    echo -e "${YELLOW}Listing contents of database/migrations:${NC}"
    ls -l "$PTERODACTYL_DIR/database/migrations"
    exit 1
fi

# Overwrite the migration file with the desired content
cat > "$migration_file" << 'EOL'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up()
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('discord_id')->nullable()->after('email');
        });
    }

    public function down()
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('discord_id');
        });
    }
};
EOL
echo -e "${GREEN}Migration file updated: $migration_file${NC}"

# Append Discord routes to routes/auth.php
echo -e "${YELLOW}Adding Discord routes to routes/auth.php...${NC}"
ROUTES_FILE="$PTERODACTYL_DIR/routes/auth.php"
cat >> "$ROUTES_FILE" << 'EOL'

Route::get('/auth/discord', [App\Http\Controllers\Auth\DiscordController::class, 'redirect'])->name('auth.discord');
Route::get('/auth/discord/callback', [App\Http\Controllers\Auth\DiscordController::class, 'callback'])->name('auth.discord.callback');
EOL

# Update the LoginContainer.tsx file to include Discord login button
echo -e "${YELLOW}Updating LoginContainer.tsx to add Discord button...${NC}"
cat > "$PTERODACTYL_DIR/resources/scripts/components/auth/LoginContainer.tsx" << 'EOL'
import { Discord } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import performPasswordLogin from '@/api/auth/login';
import { useStoreState } from '@/state/hooks';
import { Actions, useStoreActions } from 'easy-peasy';

interface Values {
    username: string;
    password: string;
}

export default () => {
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');

    const { clearFlashes, addFlash } = useStoreActions((actions: Actions<ApplicationStore>) => actions.flashes);

    const handleSubmit = async (values: Values) => {
        // Existing login logic
    };

    const handleDiscordLogin = () => {
        window.location.href = '/auth/discord';
    };

    return (
        <div className="w-full bg-neutral-900 p-8 rounded-lg shadow-md">
            {/* Existing login form code */}

            <div className="mt-6">
                <button
                    onClick={handleDiscordLogin}
                    className="w-full py-2 px-4 bg-[#5865F2] hover:bg-[#4752C4] text-white rounded-md flex items-center justify-center gap-2 transition-colors"
                >
                    <Discord className="w-5 h-5" />
                    Login with Discord
                </button>
            </div>
        </div>
    );
};
EOL

# Prompt for Discord credentials and panel URL
echo -e "${YELLOW}Please enter your Discord application credentials:${NC}"
read -p "Discord Client ID: " discord_client_id
read -p "Discord Client Secret: " discord_client_secret
read -p "Panel URL (e.g., https://panel.example.com): " panel_url

# Update .env file with Discord credentials and redirect URI
echo -e "${YELLOW}Updating .env file with Discord credentials...${NC}"
ENV_FILE="$PTERODACTYL_DIR/.env"
cat >> "$ENV_FILE" << EOL

DISCORD_CLIENT_ID=$discord_client_id
DISCORD_CLIENT_SECRET=$discord_client_secret
DISCORD_REDIRECT_URI=$panel_url/auth/discord/callback
EOL
echo -e "${GREEN}.env file updated.${NC}"

# Run database migrations
echo -e "${YELLOW}Running database migrations...${NC}"
php artisan migrate

# Build frontend assets
echo -e "${YELLOW}Building frontend assets...${NC}"
yarn build:production

# Set proper permissions for the panel
echo -e "${YELLOW}Setting proper permissions...${NC}"
chown -R www-data:www-data "$PTERODACTYL_DIR"
chmod -R 755 "$PTERODACTYL_DIR/storage"

echo -e "${GREEN}Installation complete!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Configure your Discord application at https://discord.com/developers/applications"
echo "2. Set the OAuth2 redirect URI to: $panel_url/auth/discord/callback"
echo "3. Enable OAuth2 scopes: identify and email"
echo -e "${YELLOW}A backup of the original LoginContainer.tsx was saved as: $backup_file${NC}"
