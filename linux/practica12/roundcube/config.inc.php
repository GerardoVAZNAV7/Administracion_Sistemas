<?php
// ============================================================
//  config.inc.php — Roundcube · Práctica 12/13
//  Personalización institucional reprobados.com
// ============================================================

// ── Identidad institucional ──────────────────────────────────
$config['product_name']       = 'Correo Reprobados.com';
$config['username_domain']    = 'reprobados.com';
$config['mail_domain']        = 'reprobados.com';

// ── Conexión IMAP al mailserver interno ──────────────────────
$config['default_host']       = 'tls://mailserver';
$config['default_port']       = 993;
$config['imap_conn_options']  = [
    'ssl' => [
        'verify_peer'       => false,
        'verify_peer_name'  => false,
    ],
];

// ── Conexión SMTP al mailserver interno ──────────────────────
$config['smtp_server']        = 'tls://mailserver';
$config['smtp_port']          = 587;
$config['smtp_user']          = '%u';
$config['smtp_pass']          = '%p';
$config['smtp_conn_options']  = [
    'ssl' => [
        'verify_peer'       => false,
        'verify_peer_name'  => false,
    ],
];

// ── Seguridad de sesión ───────────────────────────────────────
$config['session_lifetime']   = 30;     // minutos de inactividad
$config['force_https']        = true;   // forzar HTTPS
$config['use_https']          = true;

// ── Interfaz ─────────────────────────────────────────────────
$config['skin']               = 'elastic';
$config['language']           = 'es_ES';
$config['timezone']           = 'America/Mazatlan';
$config['date_format']        = 'd/m/Y';
$config['time_format']        = 'H:i';

// ── Adjuntos ─────────────────────────────────────────────────
$config['max_message_size']   = '25M';
$config['upload_max_filesize'] = 25;    // MB

// ── Plugins habilitados ───────────────────────────────────────
$config['plugins']            = [
    'archive',
    'zipdownload',
    'managesieve',
    'emoticons',
    'vcard_attachments',
];

// ── Logging ──────────────────────────────────────────────────
$config['log_driver']         = 'file';
$config['log_dir']            = '/var/log/roundcube/';
$config['smtp_log']           = true;
$config['log_logins']         = true;
$config['log_session']        = true;
