<?php

declare(strict_types=1);

use Fisharebest\Webtrees\Contracts\UserInterface;
use Fisharebest\Webtrees\DB;
use Fisharebest\Webtrees\Registry;
use Fisharebest\Webtrees\Services\MigrationService;
use Fisharebest\Webtrees\Services\UserService;
use Fisharebest\Webtrees\Webtrees;

require dirname(__DIR__) . '/vendor/autoload.php';
Webtrees::new()->bootstrap();
$config = parse_ini_file(Webtrees::CONFIG_FILE);
DB::connect(
    driver: $config['dbtype'],
    host: $config['dbhost'],
    port: $config['dbport'],
    database: $config['dbname'],
    username: $config['dbuser'],
    password: $config['dbpass'],
    prefix: $config['tblpfx'],
    key: '',
    certificate: '',
    ca: '',
    verify_certificate: false,
);
$migrations = Registry::container()->get(MigrationService::class);
$migrations->updateSchema('\\Fisharebest\\Webtrees\\Schema', 'WT_SCHEMA_VERSION', Webtrees::SCHEMA_VERSION);
$migrations->seedDatabase();
$users = Registry::container()->get(UserService::class);
if ($users->administrators()->isNotEmpty()) {
    echo "Existing administrators preserved; bootstrap skipped.\n";
    exit(0);
}
$settings = json_decode(file_get_contents(__DIR__ . '/bootstrap.json'), true, flags: JSON_THROW_ON_ERROR);
// Never reset/promote a pre-existing non-admin account by accident.
if ($users->findByIdentifier($settings['username']) !== null || $users->findByIdentifier($settings['email']) !== null) {
    throw new RuntimeException('Bootstrap identity already exists without administrator access; resolve explicitly.');
}
$password = trim(file_get_contents(getenv('CREDENTIALS_DIRECTORY') . '/bootstrap-password'));
if (strlen($password) < 16) {
    throw new RuntimeException('Bootstrap password must contain at least 16 characters.');
}
DB::transaction(static function () use ($users, $settings, $password): void {
    $admin = $users->create($settings['username'], $settings['name'], $settings['email'], $password);
    $admin->setPreference(UserInterface::PREF_LANGUAGE, $settings['language']);
    $admin->setPreference(UserInterface::PREF_IS_ADMINISTRATOR, '1');
    $admin->setPreference(UserInterface::PREF_IS_EMAIL_VERIFIED, '1');
    $admin->setPreference(UserInterface::PREF_IS_ACCOUNT_APPROVED, '1');
});
echo "Initial administrator created.\n";
