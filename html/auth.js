// ─────────────────────────────────────────────────────────────────────────────
// SKF Auth — Supabase JS SDK (direct, no backend needed)
// ─────────────────────────────────────────────────────────────────────────────
// Bump when login/profile copy or logic changes. In DevTools → Console you should see this after a hard refresh.
var SKF_AUTH_JS_BUILD = '2026-05-08a';
console.info('[SKF] auth.js build', SKF_AUTH_JS_BUILD);

const SUPABASE_URL    = 'https://uqlpxdphikmmpdsuojil.supabase.co';
const SUPABASE_ANON   = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxbHB4ZHBoaWttbXBkc3VvamlsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTI5NDEsImV4cCI6MjA4NjM2ODk0MX0.03xQ8ltwZm_TTEAHDOHocfFKG2j_PHmL1Lzt2t-aFJU';

if (typeof window !== 'undefined') {
    window.SKF_SUPABASE_URL = SUPABASE_URL;
}

// ─────────────────────────────────────────────────────────────────────────────
// DEV-ONLY BYPASS for email confirmation (testing blocker)
// ─────────────────────────────────────────────────────────────────────────────
// When enabled, registration uses a LOCAL backend endpoint that creates the Supabase Auth user
// as already-confirmed (no confirmation email is sent), so you can login immediately and avoid
// Supabase "email rate limit exceeded" while filling the system with test data.
//
// This does NOT remove email confirmation permanently: production keeps the normal flow below.
//
// Enable conditions:
// - local dev only (file:// or localhost)
// - backend running with AuthController dev endpoint enabled (Development + DevAuth flag)
//
// To re-enable normal email confirmation during dev, set this to false.
function skfIsLocalDev() {
    var h = (location.hostname || '').toLowerCase();
    return (
        location.protocol === 'file:' ||
        h === 'localhost' ||
        h === '127.0.0.1' ||
        h === '0.0.0.0' ||
        h === '::1' ||
        h === '::'
    );
}

const SKF_DEV_BYPASS_EMAIL_CONFIRMATION = skfIsLocalDev();
// If your backend runs on a different port, change this.
// (We try both 5000 and 3000 since different setups use different ports.)
function skfDevApiBases() {
    return [
        'http://localhost:5001/api',
        'http://127.0.0.1:5001/api',
        'http://localhost:5000/api',
        'http://127.0.0.1:5000/api',
        'http://localhost:3000/api',
        'http://127.0.0.1:3000/api'
    ];
}

// LOCAL_TEST_MODE — set true to bypass Supabase and use localStorage only
const LOCAL_TEST_MODE = false;
const LOCAL_USERS_KEY = 'skf_local_users';

// ── Sign-in method (switch when you finish testing) ───────────────────────────
// 'password' = email + password only — NO OTP emails, no rate limits on codes.
//              Set each user's password: Supabase Dashboard → Authentication → Users → user → ⋮ → Set password.
// 'otp'       = email one-time code (normal production behavior).
const SKF_AUTH_MODE = 'password';

var EMAIL_CODE_STORAGE_KEY = 'skf_email_code_login';
var STAFF_EMAIL_CODE_STORAGE_KEY = 'skf_staff_email_code_login';

// Supabase Auth: "Confirm email" must be enabled (Auth → Providers → Email) for registration flows.
//
// index.html: member sign-in is email OTP only (player / coach / club_admin). Magic Link template needs {{ .Token }}.
// skf-admin-login.html: federation staff only — email OTP (SKF Admin, referee, referees+). Same Supabase email template ({{ .Token }}).

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
        case 'referees':
        case 'referee_plus':
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

/** Staff portal: resolve official ID (or username) to the account email Supabase Auth uses. OTP is always sent to that email. */
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
        showErr('Unable to look up this ID. If the problem persists, sign in with your email instead.');
        return null;
    }
    var row = Array.isArray(r.data) ? r.data[0] : r.data;
    var em = row && (row.email || row);
    if (typeof em !== 'string' || !em.includes('@')) {
        showErr('No federation account found for this ID. Use the email you registered with, or check your SKF official ID.');
        return null;
    }
    return em.trim().toLowerCase();
}

/** Federation roles allowed on skf-admin-login (email OTP only). */
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

/** Ensure REST calls use the new JWT immediately (avoids rare races right after sign-in). */
async function applySessionForDb(sb, session) {
    if (!session || !session.access_token || !session.refresh_token) return;
    var out = await sb.auth.setSession({
        access_token:  session.access_token,
        refresh_token: session.refresh_token
    });
    if (out && out.error) {
        console.warn('setSession before profile load:', out.error);
    }
}

/**
 * Load public.users for the signed-in user. Prefer RPC get_my_profile() (SECURITY DEFINER)
 * when present in the database — fixes broken/missing RLS on direct table SELECT.
 */
async function fetchUserProfileRow(sb, session, userId) {
    await applySessionForDb(sb, session);

    var rpc = await sb.rpc('get_my_profile');
    if (!rpc.error && rpc.data != null) {
        var rows = Array.isArray(rpc.data) ? rpc.data : [rpc.data];
        var row0 = rows.length ? rows[0] : null;
        if (row0) {
            return { data: row0, error: null };
        }
    } else if (rpc.error) {
        var rm = (rpc.error.message || rpc.error.code || '').toLowerCase();
        if (!/function|schema cache|rpc|not found|pgrst202/i.test(rm)) {
            console.warn('get_my_profile RPC:', rpc.error);
        }
    }

    return await sb.from('users').select('*').eq('id', userId).single();
}

function describeProfileLoadFailure(profileRes) {
    var err = profileRes && profileRes.error;
    if (err) {
        console.error('Profile load (technical):', err.code || '', err.message || err);
    } else {
        console.error('Profile load: no row in public.users for this session (or RPC returned empty).');
    }
    return 'Contact SKF support if this continues — your account may need to be linked in the federation directory.';
}

// Member portal: shared checks after Supabase session exists (OTP verify or password login).
async function afterMemberSupabaseAuth(sb, session, userId, showErr) {
    var profileRes = await fetchUserProfileRow(sb, session, userId);
    var profile = profileRes.data;
    if (profileRes.error || !profile) {
        await sb.auth.signOut();
        console.error('Member profile load failed', profileRes.error || '(no row)');
        showErr('Signed in, but your SKF profile could not be loaded. ' + describeProfileLoadFailure(profileRes));
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

    localStorage.setItem('token', session.access_token);
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
    return true;
}

// Shared path after Supabase Auth session is established (password or OTP).
async function finishSupabaseLogin(sb, session, userId, showErr, requireSkfAdminRole) {
    var profileRes = await fetchUserProfileRow(sb, session, userId);
    var profile = profileRes.data;
    if (profileRes.error || !profile) {
        await sb.auth.signOut();
        console.error('Profile load failed', profileRes.error || '(no row)');
        showErr('Signed in, but your SKF profile could not be loaded. ' + describeProfileLoadFailure(profileRes));
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
/** Supabase Auth throttles OTP emails — show a clear message when the API returns rate limit. */
function mapSupabaseOtpSendError(message) {
    var m = (message || '').toLowerCase();
    if (/rate limit|over_email_send_rate|too many|email_send/.test(m)) {
        return 'Too many sign-in codes were sent recently. Please wait before requesting another code, and avoid clicking send repeatedly.';
    }
    return null;
}

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
            var mapped = mapSupabaseOtpSendError(error.message);
            var m = mapped || error.message || 'Could not send code.';
            if (!mapped && /signups not allowed|not found|invalid/i.test(m)) {
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

        await afterMemberSupabaseAuth(sb, data.session, data.user.id, showErr);
    } catch (err) {
        console.error(err);
        showErr('Something went wrong. Try again.');
    }
    return false;
}

/** When SKF_AUTH_MODE === 'password' — same Supabase session as OTP, no emails sent. */
async function handleMemberPasswordLogin(event) {
    if (event && event.preventDefault) event.preventDefault();
    var errEl = document.getElementById('passwordLoginError') || document.getElementById('loginError');
    function showErr(msg) {
        if (errEl) {
            errEl.textContent = msg;
            errEl.style.display = 'block';
        } else {
            alert(msg);
        }
    }

    if (LOCAL_TEST_MODE) {
        showErr('Not available in LOCAL_TEST_MODE.');
        return false;
    }

    try {
        const sb = getSupabase();
        if (!sb) {
            showErr('Auth service unavailable.');
            return false;
        }
        var emailEl = document.getElementById('memberPasswordEmail') || document.getElementById('email');
        var passwordField = document.getElementById('memberPasswordField') || document.getElementById('password');
        var email = (emailEl && emailEl.value || '').trim().toLowerCase();
        var password = passwordField ? passwordField.value : '';
        if (!email || !password) {
            showErr('Enter email and password.');
            return false;
        }

        const { data, error } = await sb.auth.signInWithPassword({
            email: email,
            password: password
        });

        if (error || !data.session || !data.user) {
            var em = (error && error.message) || 'Invalid email or password.';
            if (String(em).toLowerCase().indexOf('email not confirmed') !== -1) {
                em = 'Please confirm your email using the link that was sent when the account was created, then try again.';
            }
            showErr(em);
            return false;
        }

        await afterMemberSupabaseAuth(sb, data.session, data.user.id, showErr);
    } catch (err) {
        console.error(err);
        showErr('Something went wrong. Try again.');
    }
    return false;
}

/** Staff portal password sign-in when SKF_AUTH_MODE === 'password'. */
async function handleStaffPasswordLogin(event) {
    if (event && event.preventDefault) event.preventDefault();
    var errEl = document.getElementById('staffOtpError');
    var okEl = document.getElementById('staffOtpHint');
    function showErr(msg) {
        if (okEl) {
            okEl.style.display = 'none';
            okEl.textContent = '';
        }
        if (errEl) {
            errEl.textContent = msg;
            errEl.style.display = 'block';
        } else {
            alert(msg);
        }
    }

    if (LOCAL_TEST_MODE) {
        showErr('Not available in LOCAL_TEST_MODE.');
        return false;
    }

    try {
        const sb = getSupabase();
        if (!sb) {
            showErr('Auth service unavailable.');
            return false;
        }
        var raw = (document.getElementById('staffPasswordIdentity') && document.getElementById('staffPasswordIdentity').value || '').trim();
        var pwField = document.getElementById('staffPasswordField');
        var password = pwField ? pwField.value : '';
        if (!raw || !password) {
            showErr('Enter email or SKF ID and password.');
            return false;
        }

        var emailForAuth = await resolveStaffIdentifierToEmail(sb, raw, showErr);
        if (!emailForAuth) return false;

        const { data, error } = await sb.auth.signInWithPassword({
            email: emailForAuth,
            password: password
        });

        if (error || !data.session || !data.user) {
            var errMsg = (error && error.message) || '';
            var low = String(errMsg).toLowerCase();
            var friendly = 'Invalid email or password. Check your details and try again.';
            if (low.indexOf('email not confirmed') !== -1 || low.indexOf('not confirmed') !== -1) {
                friendly = 'Please confirm your email using the link that was sent when the account was created, then try again.';
            } else if (low.indexOf('invalid login') !== -1 || low.indexOf('invalid credentials') !== -1) {
                friendly = 'Invalid email or password. Check your details and try again.';
            }
            showErr(friendly);
            return false;
        }

        await finishSupabaseLogin(sb, data.session, data.user.id, showErr, true);
    } catch (err) {
        console.error(err);
        showErr('Something went wrong. Try again.');
    }
    return false;
}

function initAuthModeUI() {
    var isPw = SKF_AUTH_MODE === 'password';

    var otpMember = document.getElementById('loginEmailCodePanel');
    var pwMember = document.getElementById('loginPasswordPanel');
    if (otpMember && pwMember) {
        otpMember.style.display = isPw ? 'none' : 'block';
        pwMember.style.display = isPw ? 'block' : 'none';
    }

    var intro = document.getElementById('memberLoginIntro');
    if (intro) {
        if (isPw) {
            intro.innerHTML = 'For <strong>player</strong>, <strong>coach</strong>, and <strong>club admin</strong>. '
                + 'Sign in with the email and password for your SKF account.';
        } else {
            intro.innerHTML = 'For <strong>player</strong>, <strong>coach</strong>, and <strong>club admin</strong> only. '
                + 'Enter your registered email — we send a one-time code. No password on this page.';
        }
    }

    var staffOtpPanel = document.getElementById('staffEmailCodePanel');
    var staffPwPanel = document.getElementById('staffPasswordPanel');
    if (staffOtpPanel && staffPwPanel) {
        staffOtpPanel.style.display = isPw ? 'none' : 'block';
        staffPwPanel.style.display = isPw ? 'block' : 'none';
    }

    var staffIntro = document.getElementById('staffLoginIntro');
    if (staffIntro) {
        if (isPw) {
            staffIntro.innerHTML = 'For <strong>SKF Administrators</strong>, <strong>referees</strong>, and <strong>Referees+</strong>. '
                + 'Sign in with your federation email or official SKF ID and your password.';
        } else {
            staffIntro.innerHTML = 'For <strong>SKF Administrators</strong>, <strong>referees</strong>, and <strong>Referees+</strong>. '
                + 'Sign in with your <strong>email</strong> or your <strong>SKF official ID</strong> (or username). '
                + 'The one-time code is sent to the <strong>email linked to that account</strong>.';
        }
    }

    var buildEl = document.getElementById('skfAuthBuild');
    if (buildEl && typeof SKF_AUTH_JS_BUILD !== 'undefined') {
        buildEl.textContent = 'Auth build ' + SKF_AUTH_JS_BUILD + ' — if this line never updates, you are not loading this project’s html folder.';
    }
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initAuthModeUI);
} else {
    initAuthModeUI();
}

window.handleSendEmailCode = handleSendEmailCode;
window.handleVerifyEmailCode = handleVerifyEmailCode;
window.handleLogin = handleLogin;
window.handleMemberPasswordLogin = handleMemberPasswordLogin;
window.handleStaffPasswordLogin = handleStaffPasswordLogin;

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
            var mapped = mapSupabaseOtpSendError(error.message);
            var m = mapped || error.message || 'Could not send code.';
            if (!mapped && /signups not allowed|not found|invalid/i.test(m)) {
                m = 'Unable to send a code for this account.';
            }
            showErr(m);
            return false;
        }

        try { sessionStorage.setItem(STAFF_EMAIL_CODE_STORAGE_KEY, emailForAuth); } catch (_) {}
        var otpRow = document.getElementById('staffOtpCodeRow');
        if (otpRow) otpRow.style.display = 'block';
        if (btnSend) { btnSend.disabled = false; btnSend.textContent = 'Resend code'; }
        var usedId = (raw.indexOf('@') === -1);
        showOk(
            usedId
                ? 'Code sent to the email address on file for that ID (the same email as your SKF / Supabase account). Check inbox and spam.'
                : 'Check your email for the one-time code (and spam).'
        );
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
    function showSuccess(role, opts) {
        opts = opts || {};
        if (form) form.style.display = 'none';
        if (errEl) errEl.style.display = 'none';
        if (sucEl) {
            const isPlayer   = role === 'player';
            const needsAdmin = needsApproval(role);
            const verifyLine = opts.devBypassEmail
                ? '<p style="margin:0 0 12px;"><strong>Dev mode:</strong> email confirmation is bypassed for testing. You can sign in immediately.</p>'
                : '<p style="margin:0 0 12px;"><strong>Email verification is required for every account.</strong> ' +
                  'Use the link in the confirmation message we sent before you try to log in.</p>';
            const roleSpecific = isPlayer
                ? '<p style="margin:0;">After you confirm your email, you can sign in on the login page.</p>'
                : needsAdmin
                    ? '<p style="margin:0;"><strong>Then</strong> your profile may stay inactive until an SKF administrator approves it — you will be notified.</p>'
                    : '<p style="margin:0;">After you confirm your email, you can sign in on the login page.</p>';
            sucEl.innerHTML  =
                '<div style="text-align:center;padding:10px 0;">' +
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

    // Prevent duplicate clicks / repeated signup triggers
    var submitBtn = form && form.querySelector('button[type="submit"]');
    var submitBtnText = submitBtn ? (submitBtn.textContent || '') : '';
    function setBusy(busy) {
        if (!submitBtn) return;
        submitBtn.disabled = !!busy;
        submitBtn.textContent = busy ? 'Creating…' : (submitBtnText || 'Register');
    }

    var lockKey = 'skf_signup_lock_' + email;
    try {
        var last = parseInt(sessionStorage.getItem(lockKey) || '0', 10) || 0;
        if (Date.now() - last < 15000) {
            showErr('Please wait a few seconds before trying again.');
            return false;
        }
        sessionStorage.setItem(lockKey, String(Date.now()));
    } catch (_) {}

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
        setBusy(true);

        // DEV BYPASS: create confirmed users via backend (no confirmation email)
        if (SKF_DEV_BYPASS_EMAIL_CONFIRMATION) {
            var ageEl2 = document.getElementById('age-group');
            var beltEl2 = document.getElementById('belt-rank');
            var catEl2 = document.getElementById('player-category');

            var devPayload = {
                fullName: fullName,
                nationalId: nationalId,
                phone: phone,
                email: email,
                password: password,
                role: role
            };
            if (role === 'player') {
                devPayload.ageGroup = ageEl2 && ageEl2.value ? ageEl2.value : '';
                devPayload.rank = beltEl2 && beltEl2.value ? beltEl2.value : '';
                devPayload.playerCategory = catEl2 && catEl2.value ? catEl2.value : '';
            }

            var bases = skfDevApiBases();
            var lastErr = '';
            var devOk = false;
            for (var bi = 0; bi < bases.length; bi++) {
                try {
                    var devRes = await fetch(bases[bi] + '/auth/dev-register', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(devPayload)
                    });
                    var devText = await devRes.text();
                    if (devRes.ok) {
                        devOk = true;
                        break;
                    }
                    lastErr = devText || ('HTTP ' + devRes.status);
                } catch (e) {
                    lastErr = (e && e.message) ? e.message : String(e || 'Failed to fetch');
                }
            }
            if (!devOk) {
                showErr(
                    'Dev bypass is ON, but the backend dev endpoint is not reachable.\n\n' +
                    'Fix:\n' +
                    '1) Run backend: cd /Users/yosef_naytah/Documents/SKF_WEBSITE/backend/SkfWebsite.Api && dotnet run\n' +
                    '2) Make sure you set SUPABASE_SERVICE_ROLE_KEY in that terminal.\n' +
                    '3) Open REGISTER via http://localhost:5500 (recommended) instead of file:// if you still see blocks.\n\n' +
                    'Last error: ' + lastErr
                );
                setBusy(false);
                return false;
            }

            showSuccess(role, { devBypassEmail: true });
            setBusy(false);
            return false;
        }

        const sb = getSupabase();
        if (!sb) { showErr('Auth service unavailable.'); return false; }

        // After email confirmation, browser must land on a page that runs PKCE exchange
        var path = window.location.pathname || '';
        var dir  = path.substring(0, path.lastIndexOf('/') + 1);
        var emailRedirectTo = window.location.origin + dir + 'auth-callback.html';

        // 1. Create Supabase Auth account (metadata used by DB trigger → public.users).
        //    Phone is stored in user_metadata only (no Auth phone provider required).
        var meta = {
            full_name:   fullName,
            role:        role,
            national_id: nationalId,
            phone:       phone,
            club_name:   ''
        };
        if (role === 'player') {
            var ageEl = document.getElementById('age-group');
            var beltEl = document.getElementById('belt-rank');
            var catEl = document.getElementById('player-category');
            meta.age_group = ageEl && ageEl.value ? ageEl.value : '';
            meta.rank = beltEl && beltEl.value ? beltEl.value : '';
            meta.player_category = catEl && catEl.value ? catEl.value : '';
        }
        var signUpBody = {
            email,
            password,
            options: {
                emailRedirectTo: emailRedirectTo,
                data: meta
            }
        };
        const { data, error } = await sb.auth.signUp(signUpBody);

        if (error) {
            var emsg = String(error.message || '');
            if (/rate limit/i.test(emsg)) {
                showErr('Email rate limit exceeded. Please wait and try again. (Tip: in local testing we can enable dev bypass so no confirmation email is sent.)');
            } else {
                showErr(error.message);
            }
            setBusy(false);
            return false;
        }
        if (!data.user) { showErr('Registration failed. Please try again.'); return false; }

        // 2. public.users row is created by DB trigger (database/supabase_auth_profile_trigger.sql).
        //    Required when "Confirm email" is ON (no session yet → browser cannot INSERT past RLS).

        showSuccess(role);
        setBusy(false);

    } catch (err) {
        console.error(err);
        showErr('An error occurred. Please try again.');
        setBusy(false);
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

/**
 * Build a usable <img src> from a Supabase Storage path or full URL.
 * baseUrl is usually the project URL (e.g. window.SKF_SUPABASE_URL); if omitted, SKF_SUPABASE_URL is used in browsers.
 */
function skfResolveAvatarUrl(urlOrPath, baseUrl) {
    if (urlOrPath == null || urlOrPath === '') return '';
    var s = String(urlOrPath).trim();
    if (!s) return '';
    var lower = s.toLowerCase();
    if (lower.indexOf('https://') === 0 || lower.indexOf('http://') === 0 || lower.indexOf('data:') === 0 || lower.indexOf('blob:') === 0) {
        return s;
    }
    var path = s.replace(/^\/+/, '');
    var b = '';
    if (baseUrl != null && String(baseUrl).trim() !== '') {
        b = String(baseUrl).replace(/\/+$/, '');
    } else if (typeof window !== 'undefined' && window.SKF_SUPABASE_URL) {
        b = String(window.SKF_SUPABASE_URL).replace(/\/+$/, '');
    }
    if (!b) return s;
    if (path.indexOf('storage/v1') === 0) {
        return b + '/' + path;
    }
    return b + '/storage/v1/object/public/' + path;
}

/** Pick the best raw avatar field from a users row (optional nested profiles). */
function skfAvatarRawFromRow(row) {
    if (!row || typeof row !== 'object') return '';
    var p = row.profiles;
    if (p && typeof p === 'object' && !Array.isArray(p) && p.avatar_url) {
        var a0 = String(p.avatar_url).trim();
        if (a0) return a0;
    }
    if (Array.isArray(p) && p.length && p[0] && p[0].avatar_url) {
        var a1 = String(p[0].avatar_url).trim();
        if (a1) return a1;
    }
    if (row.avatar_url) {
        var a2 = String(row.avatar_url).trim();
        if (a2) return a2;
    }
    if (row.profile_image_url) {
        var i0 = String(row.profile_image_url).trim();
        if (i0) return i0;
    }
    if (row.profile_photo_url) {
        var ph = String(row.profile_photo_url).trim();
        if (ph) return ph;
    }
    return '';
}

window.getSupabase = getSupabase;
window.skfResolveAvatarUrl = skfResolveAvatarUrl;
window.skfAvatarRawFromRow = skfAvatarRawFromRow;
