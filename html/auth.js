// ─────────────────────────────────────────────────────────────────────────────
// SKF Auth — Supabase JS SDK (direct, no backend needed)
// ─────────────────────────────────────────────────────────────────────────────

const SUPABASE_URL    = 'https://uqlpxdphikmmpdsuojil.supabase.co';
const SUPABASE_ANON   = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxbHB4ZHBoaWttbXBkc3VvamlsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTI5NDEsImV4cCI6MjA4NjM2ODk0MX0.03xQ8ltwZm_TTEAHDOHocfFKG2j_PHmL1Lzt2t-aFJU';

// LOCAL_TEST_MODE — set true to bypass Supabase and use localStorage only
const LOCAL_TEST_MODE = false;
const LOCAL_USERS_KEY = 'skf_local_users';

// Supabase Auth: "Confirm email" must be enabled (Auth → Providers → Email) for registration flows.
//
// index.html: member sign-in is email OTP only (player / coach / club_admin). Magic Link template needs {{ .Token }}.
// skf-admin-login.html (SKF Admin portal): password tab OR "Email code (OTP)" tab — same Supabase Magic Link template as members ({{ .Token }}).

// ── Supabase client (only used when LOCAL_TEST_MODE = false) ──────────────────
let _supabase = null;
function getSupabase() {
    if (!_supabase && typeof supabase !== 'undefined') {
        _supabase = supabase.createClient(SUPABASE_URL, SUPABASE_ANON, {
            auth: {
                detectSessionInUrl: true,
                flowType: 'pkce'
            }
        });
    }
    return _supabase;
}

// ── Role helpers ──────────────────────────────────────────────────────────────
function getDashboardUrl(role) {
    switch ((role || '').toLowerCase()) {
        case 'skf_admin':
        case 'admin':
            return 'admin-dashboard.html';
        case 'player':
            return 'player-dashboard.html';
        case 'referee':
        case 'referees_plus':
            return 'referee-dashboard.html';
        case 'coach':
            return 'coach-dashboard.html';
        case 'club_admin':
            return 'club-dashboard.html';
        default:
            return 'player-dashboard.html';
    }
}

function formatRoleName(role) {
    const map = {
        'skf_admin':     'SKF Admin',
        'admin':         'SKF Admin',
        'player':        'Player',
        'coach':         'Coach',
        'referee':       'Referee',
        'club_admin':    'Club Admin',
        'referees_plus': 'Referees +'
    };
    return map[(role || '').toLowerCase()] || role;
}

// Roles that need SKF Admin approval before they can log in (SKF Admins are provisioned, not self-registered)
function needsApproval(role) {
    return ['coach', 'referee', 'referees_plus', 'club_admin'].includes(
        (role || '').toLowerCase()
    );
}

/** Roles allowed to use passwordless email code on the main login page (not federation staff). */
function emailCodeAllowedRole(role) {
    const r = (role || '').toLowerCase();
    return r === 'player' || r === 'coach' || r === 'club_admin';
}

/**
 * Normalize Saudi-style mobile to E.164 (+9665…). Returns '' if invalid.
 * Accepts: 05xxxxxxxx, 5xxxxxxxx, 9665xxxxxxxx, +9665xxxxxxxx
 */
function normalizeSaudiMobileE164(raw) {
    var s = String(raw || '').replace(/\s/g, '');
    if (!s) return '';
    var digits = s.replace(/^\+/, '').replace(/\D/g, '');
    if (digits.startsWith('966')) {
        digits = digits.slice(3);
    }
    if (digits.startsWith('0')) digits = digits.slice(1);
    if (digits.length === 9 && digits.charAt(0) === '5') {
        return '+966' + digits;
    }
    return '';
}

window.normalizeSaudiMobileE164 = normalizeSaudiMobileE164;

// ── Local storage helpers ─────────────────────────────────────────────────────
function getLocalUsers() {
    try { return JSON.parse(localStorage.getItem(LOCAL_USERS_KEY) || '[]'); }
    catch { return []; }
}
function setLocalUsers(users) {
    localStorage.setItem(LOCAL_USERS_KEY, JSON.stringify(users));
}

// If input looks like an email, use it; otherwise treat as SKF Admin login_id and resolve via RPC.
async function resolveLoginEmail(sb, rawInput, showErr) {
    var t = (rawInput || '').trim().toLowerCase();
    if (!t) {
        showErr('Enter your email or SKF Admin ID.');
        return null;
    }
    if (t.indexOf('@') !== -1) return t;

    var r = await sb.rpc('resolve_skf_admin_login_id', { p_login_id: t });
    if (r.error) {
        console.error(r.error);
        showErr('Could not look up SKF Admin ID. Check the ID or use your email on the main login page.');
        return null;
    }
    var row = Array.isArray(r.data) ? r.data[0] : r.data;
    var em = row && (row.email || row);
    if (typeof em !== 'string' || !em.includes('@')) {
        showErr('Unknown SKF Admin ID or inactive account.');
        return null;
    }
    return em.trim().toLowerCase();
}

/** Staff portal: resolve official ID to auth email (minimal error text). */
async function resolveStaffIdentifierToEmail(sb, rawInput, showErr) {
    var t = (rawInput || '').trim().toLowerCase();
    if (!t) {
        showErr('Required.');
        return null;
    }
    if (t.indexOf('@') !== -1) return t;
    var r = await sb.rpc('resolve_skf_admin_login_id', { p_login_id: t });
    if (r.error) {
        console.error(r.error);
        showErr('Unable to sign in.');
        return null;
    }
    var row = Array.isArray(r.data) ? r.data[0] : r.data;
    var em = row && (row.email || row);
    if (typeof em !== 'string' || !em.includes('@')) {
        showErr('Unable to sign in.');
        return null;
    }
    return em.trim().toLowerCase();
}

/** Federation roles allowed on skf-admin-login (password or email OTP). */
function isStaffPortalRole(role) {
    const r = (role || '').toLowerCase();
    return r === 'skf_admin' || r === 'admin' || r === 'referees_plus' || r === 'referee';
}

/** Main login (members): email only — no SKF Admin ID resolution on this page. */
function parseMemberSignInEmail(rawInput, showErr) {
    var t = (rawInput || '').trim().toLowerCase();
    if (!t) {
        showErr('Enter the email address on your SKF account.');
        return null;
    }
    if (t.indexOf('@') === -1) {
        showErr('Use your full email address (the one you registered with).');
        return null;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(t)) {
        showErr('That email address does not look valid.');
        return null;
    }
    return t;
}

// Shared path after signInWithPassword succeeds
async function finishSupabaseLogin(sb, session, userId, showErr, requireSkfAdminRole) {
    var profileRes = await sb.from('users').select('*').eq('id', userId).single();
    var profile = profileRes.data;
    if (profileRes.error || !profile) {
        await sb.auth.signOut();
        if (requireSkfAdminRole) {
            showErr('Your login worked, but your profile could not be loaded. Contact support.');
        } else {
            showErr(
                'Your login worked, but your profile row is missing in the database. ' +
                'Run database/supabase_sync_missing_profiles.sql in Supabase SQL Editor, then try again.'
            );
        }
        return false;
    }

    var r = (profile.role || '').toLowerCase();
    if (requireSkfAdminRole && !isStaffPortalRole(r)) {
        await sb.auth.signOut();
        showErr('This account is not authorized on this page.');
        return false;
    }

    if (!profile.is_active) {
        await sb.auth.signOut();
        showErr('Your account is pending SKF Admin approval. You will be notified once approved.');
        return false;
    }

    localStorage.setItem('token', session.access_token);
    localStorage.setItem('user', JSON.stringify({
        id:       profile.id,
        email:    profile.email,
        fullName: profile.full_name,
        role:     profile.role,
        username: profile.username,
        skfId:    profile.skf_official_id || profile.player_id || null
    }));

    window.location.href = getDashboardUrl(profile.role);
    return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN (players, coaches, referees, club admins — email + password)
// ─────────────────────────────────────────────────────────────────────────────
async function handleLogin(event) {
    event.preventDefault();

    const email    = document.getElementById('email').value.trim().toLowerCase();
    const password = document.getElementById('password').value;
    const errEl    = document.getElementById('loginError');

    function showErr(msg) {
        if (errEl) { errEl.textContent = msg; errEl.style.display = 'block'; }
        else alert(msg);
    }

    // ── LOCAL MODE ────────────────────────────────────────────────────────────
    if (LOCAL_TEST_MODE) {
        const users = getLocalUsers();
        const user  = users.find(u =>
            (u.email || '').toLowerCase() === email && u.password === password
        );

        if (!user) { showErr('Invalid email or password.'); return false; }

        if (!user.emailConfirmed) {
            showErr('Please confirm your email before logging in. Check your inbox.');
            return false;
        }
        if (!user.isActive) {
            showErr('Your account is pending SKF Admin approval. You will be notified once approved.');
            return false;
        }

        localStorage.setItem('token', 'local-token-' + Date.now());
        localStorage.setItem('user', JSON.stringify({
            id:       user.id,
            email:    user.email,
            fullName: user.fullName,
            role:     user.role,
            username: user.username || user.email,
            skfId:    user.skfId || null
        }));

        window.location.href = getDashboardUrl(user.role);
        return false;
    }

    // ── SUPABASE MODE ─────────────────────────────────────────────────────────
    try {
        const sb = getSupabase();
        if (!sb) { showErr('Auth service unavailable.'); return false; }

        var emailForAuth = await resolveLoginEmail(sb, email, showErr);
        if (!emailForAuth) return false;

        const { data, error } = await sb.auth.signInWithPassword({
            email:    emailForAuth,
            password: password
        });

        if (error) {
            const em = (error.message || '').toLowerCase();
            if (em.includes('email not confirmed') || em.includes('not confirmed') || em.includes('confirm your email')) {
                showErr('Email verification is required before login. Check your inbox (and spam) for the confirmation link, then try again.');
            } else if (error.message.includes('Invalid login')) {
                showErr('Invalid email / ID or password.');
            } else {
                showErr(error.message);
            }
            return false;
        }

        await finishSupabaseLogin(sb, data.session, data.user.id, showErr, false);

    } catch (err) {
        console.error(err);
        showErr('An error occurred. Please try again.');
    }

    return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN — email one-time code (player, coach, club_admin; same email as Supabase Auth)
// ─────────────────────────────────────────────────────────────────────────────
var EMAIL_CODE_STORAGE_KEY = 'skf_email_code_login';

async function handleSendEmailCode(event) {
    if (event && event.preventDefault) event.preventDefault();
    var errEl = document.getElementById('emailCodeError');
    var okEl  = document.getElementById('emailCodeHint');
    var inputEl = document.getElementById('emailCodeAddress');
    var btnSend  = document.getElementById('emailCodeSendBtn');

    function showErr(msg) {
        if (okEl) { okEl.style.display = 'none'; okEl.textContent = ''; }
        if (errEl) { errEl.textContent = msg; errEl.style.display = 'block'; }
        else alert(msg);
    }
    function showOk(msg) {
        if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }
        if (okEl) { okEl.textContent = msg; okEl.style.display = 'block'; }
    }

    if (LOCAL_TEST_MODE) {
        showErr('Email code login needs Supabase (turn off LOCAL_TEST_MODE).');
        return false;
    }

    try {
        const sb = getSupabase();
        if (!sb) { showErr('Auth service unavailable.'); return false; }

        var raw = (inputEl && inputEl.value || '').trim();
        var emailForAuth = parseMemberSignInEmail(raw, showErr);
        if (!emailForAuth) return false;

        if (btnSend) { btnSend.disabled = true; btnSend.textContent = 'Sending…'; }

        var path = window.location.pathname || '';
        var dir  = path.substring(0, path.lastIndexOf('/') + 1);
        var emailRedirectTo = window.location.origin + dir + 'auth-callback.html';

        const { error } = await sb.auth.signInWithOtp({
            email: emailForAuth,
            options: {
                shouldCreateUser: false,
                emailRedirectTo: emailRedirectTo,
            },
        });

        if (error) {
            if (btnSend) { btnSend.disabled = false; btnSend.textContent = 'Send code'; }
            var m = error.message || 'Could not send code.';
            if (/signups not allowed|not found|invalid/i.test(m)) {
                m = 'No account with this email, or sign-in is not allowed. Register first, or use the email you signed up with.';
            }
            showErr(m);
            return false;
        }

        try { sessionStorage.setItem(EMAIL_CODE_STORAGE_KEY, emailForAuth); } catch (_) {}
        var otpRow = document.getElementById('emailCodeRow');
        if (otpRow) otpRow.style.display = 'block';
        if (btnSend) { btnSend.disabled = false; btnSend.textContent = 'Resend code'; }
        showOk('Check your email for the one-time code (and spam). Enter it below.');
    } catch (err) {
        console.error(err);
        if (btnSend) { btnSend.disabled = false; btnSend.textContent = 'Send code'; }
        showErr('Something went wrong. Try again.');
    }
    return false;
}

async function handleVerifyEmailCode(event) {
    if (event && event.preventDefault) event.preventDefault();
    var errEl = document.getElementById('emailCodeError');
    var okEl  = document.getElementById('emailCodeHint');

    function showErr(msg) {
        if (okEl) { okEl.style.display = 'none'; okEl.textContent = ''; }
        if (errEl) { errEl.textContent = msg; errEl.style.display = 'block'; }
        else alert(msg);
    }

    if (LOCAL_TEST_MODE) {
        showErr('Email code login needs Supabase.');
        return false;
    }

    var emailStored = '';
    try { emailStored = sessionStorage.getItem(EMAIL_CODE_STORAGE_KEY) || ''; } catch (_) {}
    if (!emailStored) {
        showErr('Send a code first.');
        return false;
    }

    var codeEl = document.getElementById('emailCodeInput');
    var token = (codeEl && codeEl.value || '').replace(/\D/g, '');
    if (token.length < 4) {
        showErr('Enter the code from your email.');
        return false;
    }

    try {
        const sb = getSupabase();
        if (!sb) { showErr('Auth service unavailable.'); return false; }

        const { data, error } = await sb.auth.verifyOtp({
            email: emailStored,
            token: token,
            type: 'email',
        });

        if (error || !data.session || !data.user) {
            showErr((error && error.message) || 'Invalid or expired code.');
            return false;
        }

        var profileRes = await sb.from('users').select('*').eq('id', data.user.id).single();
        var profile = profileRes.data;
        if (profileRes.error || !profile) {
            await sb.auth.signOut();
            showErr(
                'Your login worked, but your profile row is missing. Contact support.'
            );
            return false;
        }

        var role = (profile.role || '').toLowerCase();
        if (!emailCodeAllowedRole(role)) {
            await sb.auth.signOut();
            showErr('This sign-in page is only for player, coach, or club admin. SKF Admin and federation staff should use the SKF Admin portal.');
            return false;
        }

        if (!profile.is_active) {
            await sb.auth.signOut();
            showErr('Your account is pending SKF Admin approval. You will be notified once approved.');
            return false;
        }

        localStorage.setItem('token', data.session.access_token);
        localStorage.setItem('user', JSON.stringify({
            id:       profile.id,
            email:    profile.email,
            fullName: profile.full_name,
            role:     profile.role,
            username: profile.username,
            skfId:    profile.skf_official_id || profile.player_id || null
        }));

        try { sessionStorage.removeItem(EMAIL_CODE_STORAGE_KEY); } catch (_) {}
        window.location.href = getDashboardUrl(profile.role);
    } catch (err) {
        console.error(err);
        showErr('Something went wrong. Try again.');
    }
    return false;
}

window.handleSendEmailCode = handleSendEmailCode;
window.handleVerifyEmailCode = handleVerifyEmailCode;

var STAFF_EMAIL_CODE_STORAGE_KEY = 'skf_staff_email_code_login';

async function handleSendStaffEmailCode(event) {
    if (event && event.preventDefault) event.preventDefault();
    var errEl = document.getElementById('staffOtpError');
    var okEl  = document.getElementById('staffOtpHint');
    var inputEl = document.getElementById('staffOtpIdField');
    var btnSend = document.getElementById('staffOtpSendBtn');

    function showErr(msg) {
        if (okEl) { okEl.style.display = 'none'; okEl.textContent = ''; }
        if (errEl) { errEl.textContent = msg; errEl.style.display = 'block'; }
        else alert(msg);
    }
    function showOk(msg) {
        if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }
        if (okEl) { okEl.textContent = msg; okEl.style.display = 'block'; }
    }

    if (LOCAL_TEST_MODE) {
        showErr('Email code needs Supabase.');
        return false;
    }

    try {
        const sb = getSupabase();
        if (!sb) { showErr('Auth service unavailable.'); return false; }

        var raw = (inputEl && inputEl.value || '').trim();
        var emailForAuth = await resolveStaffIdentifierToEmail(sb, raw, showErr);
        if (!emailForAuth) return false;

        if (btnSend) { btnSend.disabled = true; btnSend.textContent = 'Sending…'; }

        var path = window.location.pathname || '';
        var dir  = path.substring(0, path.lastIndexOf('/') + 1);
        var emailRedirectTo = window.location.origin + dir + 'auth-callback.html';

        const { error } = await sb.auth.signInWithOtp({
            email: emailForAuth,
            options: {
                shouldCreateUser: false,
                emailRedirectTo: emailRedirectTo,
            },
        });

        if (error) {
            if (btnSend) { btnSend.disabled = false; btnSend.textContent = 'Send code'; }
            var m = error.message || 'Could not send code.';
            if (/signups not allowed|not found|invalid/i.test(m)) {
                m = 'Unable to send a code for this account.';
            }
            showErr(m);
            return false;
        }

        try { sessionStorage.setItem(STAFF_EMAIL_CODE_STORAGE_KEY, emailForAuth); } catch (_) {}
        var otpRow = document.getElementById('staffOtpCodeRow');
        if (otpRow) otpRow.style.display = 'block';
        if (btnSend) { btnSend.disabled = false; btnSend.textContent = 'Resend code'; }
        showOk('Check your email for the one-time code.');
    } catch (err) {
        console.error(err);
        if (btnSend) { btnSend.disabled = false; btnSend.textContent = 'Send code'; }
        showErr('Something went wrong. Try again.');
    }
    return false;
}

async function handleVerifyStaffEmailCode(event) {
    if (event && event.preventDefault) event.preventDefault();
    var errEl = document.getElementById('staffOtpError');
    var okEl  = document.getElementById('staffOtpHint');

    function showErr(msg) {
        if (okEl) { okEl.style.display = 'none'; okEl.textContent = ''; }
        if (errEl) { errEl.textContent = msg; errEl.style.display = 'block'; }
        else alert(msg);
    }

    if (LOCAL_TEST_MODE) {
        showErr('Email code needs Supabase.');
        return false;
    }

    var emailStored = '';
    try { emailStored = sessionStorage.getItem(STAFF_EMAIL_CODE_STORAGE_KEY) || ''; } catch (_) {}
    if (!emailStored) {
        showErr('Send a code first.');
        return false;
    }

    var codeEl = document.getElementById('staffOtpCodeInput');
    var token = (codeEl && codeEl.value || '').replace(/\D/g, '');
    if (token.length < 4) {
        showErr('Enter the code from your email.');
        return false;
    }

    try {
        const sb = getSupabase();
        if (!sb) { showErr('Auth service unavailable.'); return false; }

        const { data, error } = await sb.auth.verifyOtp({
            email: emailStored,
            token: token,
            type: 'email',
        });

        if (error || !data.session || !data.user) {
            showErr((error && error.message) || 'Invalid or expired code.');
            return false;
        }

        try { sessionStorage.removeItem(STAFF_EMAIL_CODE_STORAGE_KEY); } catch (_) {}
        await finishSupabaseLogin(sb, data.session, data.user.id, showErr, true);
    } catch (err) {
        console.error(err);
        showErr('Something went wrong. Try again.');
    }
    return false;
}

window.handleSendStaffEmailCode = handleSendStaffEmailCode;
window.handleVerifyStaffEmailCode = handleVerifyStaffEmailCode;

window.showStaffLoginMode = function (mode) {
    var passP = document.getElementById('staffPasswordPanel');
    var codeP = document.getElementById('staffEmailCodePanel');
    var bPass = document.getElementById('tabStaffPassword');
    var bCode = document.getElementById('tabStaffEmailCode');
    if (!passP || !codeP) return;
    var isPassword = mode === 'password';
    passP.style.display = isPassword ? 'block' : 'none';
    codeP.style.display = isPassword ? 'none' : 'block';
    if (bPass) {
        bPass.setAttribute('aria-selected', isPassword ? 'true' : 'false');
        bPass.style.fontWeight = isPassword ? '700' : '500';
        bPass.style.borderBottomColor = isPassword ? '#2e7d32' : 'transparent';
    }
    if (bCode) {
        bCode.setAttribute('aria-selected', !isPassword ? 'true' : 'false');
        bCode.style.fontWeight = !isPassword ? '700' : '500';
        bCode.style.borderBottomColor = !isPassword ? '#2e7d32' : 'transparent';
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// SKF Admin portal — password sign-in
// ─────────────────────────────────────────────────────────────────────────────
async function handleSkfAdminLogin(event) {
    event.preventDefault();

    var idEl   = document.getElementById('skfAdminId');
    var passEl = document.getElementById('adminPassword');
    var errEl  = document.getElementById('adminLoginError');

    function showErr(msg) {
        if (errEl) { errEl.textContent = msg; errEl.style.display = 'block'; }
        else alert(msg);
    }

    if (LOCAL_TEST_MODE) {
        showErr('SKF Admin Supabase login is disabled in local test mode.');
        return false;
    }

    var loginId = (idEl && idEl.value || '').trim();
    var password = passEl && passEl.value;

    if (!loginId || !password) {
        showErr('Required.');
        return false;
    }

    try {
        const sb = getSupabase();
        if (!sb) { showErr('Auth service unavailable.'); return false; }

        var emailForAuth = await resolveStaffIdentifierToEmail(sb, loginId, showErr);
        if (!emailForAuth) return false;

        const { data, error } = await sb.auth.signInWithPassword({
            email:    emailForAuth,
            password: password
        });

        if (error) {
            const em = (error.message || '').toLowerCase();
            if (em.includes('email not confirmed') || em.includes('not confirmed') || em.includes('confirm your email')) {
                showErr('Confirm your email before signing in.');
            } else {
                showErr('Unable to sign in.');
            }
            return false;
        }

        await finishSupabaseLogin(sb, data.session, data.user.id, showErr, true);

    } catch (err) {
        console.error(err);
        showErr('An error occurred. Please try again.');
    }

    return false;
}

if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', function () {
        if (typeof showStaffLoginMode === 'function' && document.getElementById('staffPasswordPanel')) {
            showStaffLoginMode('password');
        }
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// REGISTER
// ─────────────────────────────────────────────────────────────────────────────
async function handleRegister(event) {
    event.preventDefault();

    if (!validateForm(event)) return false;

    const form       = event.target;
    const fullName   = form.querySelector('[name="full-name"]').value.trim();
    const nationalId = form.querySelector('[name="national-id"]').value.trim();
    const phone      = form.querySelector('[name="phone"]').value.trim();
    const email      = form.querySelector('[name="email"]').value.trim().toLowerCase();
    const role       = form.querySelector('[name="user-role"]').value;
    const password   = form.querySelector('[name="password"]').value;

    const disallowedMemberFormRoles = ['skf_admin', 'admin', 'referee', 'referees_plus'];
    if (disallowedMemberFormRoles.includes((role || '').toLowerCase())) {
        var re = document.getElementById('registerError');
        if (re) {
            re.innerHTML =
                'That role is not created on this form. <a href="registration.html">Go to the registration menu</a> and use <strong>federation staff</strong> registration for SKF Admin or Referees+, or contact the federation for match official accounts.';
            re.style.display = 'block';
        } else {
            alert('Use the registration menu for federation staff (SKF Admin or Referees+). This page is only for players, coaches, and club administrators.');
        }
        return false;
    }

    const errEl = document.getElementById('registerError');
    const sucEl = document.getElementById('registerSuccess');

    function showErr(msg) {
        if (errEl) { errEl.textContent = msg; errEl.style.display = 'block'; }
        else alert(msg);
        if (sucEl) sucEl.style.display = 'none';
    }
    function showSuccess(role) {
        if (form) form.style.display = 'none';
        if (errEl) errEl.style.display = 'none';
        if (sucEl) {
            const isPlayer   = role === 'player';
            const needsAdmin = needsApproval(role);
            const verifyLine =
                '<p style="margin:0 0 12px;"><strong>Email verification is required for every account.</strong> ' +
                'Use the link in the message from Supabase before you try to log in.</p>';
            const roleSpecific = isPlayer
                ? '<p style="margin:0;">After you confirm your email, you can sign in on the login page.</p>'
                : needsAdmin
                    ? '<p style="margin:0;"><strong>Then</strong> your profile may stay inactive until an SKF administrator approves it — you will be notified.</p>'
                    : '<p style="margin:0;">After you confirm your email, you can sign in on the login page.</p>';
            sucEl.innerHTML  =
                '<div style="text-align:center;padding:10px 0;">' +
                '<div style="font-size:48px;margin-bottom:12px;">✅</div>' +
                '<h3 style="color:#2e7d44;margin:0 0 10px;">Registration successful</h3>' +
                verifyLine +
                roleSpecific +
                '<a href="index.html" style="display:inline-block;margin-top:16px;padding:10px 28px;' +
                'background:#3a7d44;color:#fff;border-radius:8px;text-decoration:none;font-weight:bold;">Continue to sign-in</a>' +
                '</div>';
            sucEl.style.display = 'block';
        } else {
            alert('Registration successful! Please check your email to confirm your account.');
            window.location.href = 'index.html';
        }
    }

    // ── LOCAL MODE ────────────────────────────────────────────────────────────
    if (LOCAL_TEST_MODE) {
        const users    = getLocalUsers();
        const existing = users.find(u => (u.email || '').toLowerCase() === email);
        if (existing) { showErr('This email is already registered.'); return false; }

        const isPlayer = role === 'player';
        users.push({
            id:             'local-' + Date.now(),
            fullName,
            nationalId,
            playerId:       nationalId,
            phone,
            email,
            username:       email,
            password,
            role,
            emailConfirmed: false,   // must confirm email
            isActive:       isPlayer, // players auto-active; others wait for admin
            skfId:          null,
            createdAt:      new Date().toISOString()
        });
        setLocalUsers(users);
        showSuccess(role);
        return false;
    }

    // ── SUPABASE MODE ─────────────────────────────────────────────────────────
    try {
        const sb = getSupabase();
        if (!sb) { showErr('Auth service unavailable.'); return false; }

        // After email confirmation, browser must land on a page that runs PKCE exchange
        var path = window.location.pathname || '';
        var dir  = path.substring(0, path.lastIndexOf('/') + 1);
        var emailRedirectTo = window.location.origin + dir + 'auth-callback.html';

        // 1. Create Supabase Auth account (metadata used by DB trigger → public.users).
        //    Phone is stored in user_metadata only (no Auth phone provider required).
        var signUpBody = {
            email,
            password,
            options: {
                emailRedirectTo: emailRedirectTo,
                data: {
                    full_name:   fullName,
                    role:        role,
                    national_id: nationalId,
                    phone:       phone,
                    club_name:   ''
                }
            }
        };
        const { data, error } = await sb.auth.signUp(signUpBody);

        if (error) { showErr(error.message); return false; }
        if (!data.user) { showErr('Registration failed. Please try again.'); return false; }

        // 2. public.users row is created by DB trigger (database/supabase_auth_profile_trigger.sql).
        //    Required when "Confirm email" is ON (no session yet → browser cannot INSERT past RLS).

        showSuccess(role);

    } catch (err) {
        console.error(err);
        showErr('An error occurred. Please try again.');
    }

    return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGOUT
// ─────────────────────────────────────────────────────────────────────────────
async function logout() {
    if (!LOCAL_TEST_MODE) {
        const sb = getSupabase();
        if (sb) await sb.auth.signOut().catch(() => {});
    }
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    window.location.href = 'index.html';
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS used by dashboards
// ─────────────────────────────────────────────────────────────────────────────
function checkAuth() {
    return !!(localStorage.getItem('token') && localStorage.getItem('user'));
}

function displayUserInfo() {
    const user   = JSON.parse(localStorage.getItem('user') || '{}');
    const el     = document.getElementById('userDisplay');
    if (el) {
        const name = user.fullName || user.email || 'User';
        el.textContent = 'Welcome, ' + name + ' (' + formatRoleName(user.role) + ')';
    }
}

