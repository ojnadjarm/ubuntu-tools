<?php
// ws.php — run one external function as a user inside the Moodle container and print only the picked fields.
// Usage: docker exec -i <container> php -- '<json {"fn","user","args","pick"}>' < ws.php
define('CLI_SCRIPT', true);
require('/var/www/html/config.php');

$job = json_decode($argv[1], true, 512, JSON_THROW_ON_ERROR);
$user = $DB->get_record_select('user', 'deleted = 0 AND (email = :e OR username = :u)',
    ['e' => $job['user'], 'u' => $job['user']], '*', MUST_EXIST);
\core\session\manager::set_user($user);

$info = \core_external\external_api::external_function_info($job['fn']);
$args = $job['args'] ?? [];
$raw = call_user_func_array([$info->classname, $info->methodname], array_values(
    \core_external\external_api::validate_parameters($info->parameters_desc, $args)));
$clean = \core_external\external_api::clean_returnvalue($info->returns_desc, $raw);

$out = [];
foreach ($job['pick'] as $path) {
    $v = $clean;
    foreach (explode('.', $path) as $k) {
        $v = is_array($v) && array_key_exists($k, $v) ? $v[$k] : null;
    }
    if (preg_match('/token|password|secret|sesskey|cookie/i', $path)) {
        $v = '<redacted>';
    }
    $out[$path] = $v;
}
echo json_encode($out, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION), "\n";
