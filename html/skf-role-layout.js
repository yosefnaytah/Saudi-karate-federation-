/**
 * SKF Role Layout — centralized route guard and referee navigation.
 * Load after auth.js. Uses dashboard.css (.dashboard-nav) styles.
 */
(function (global) {
    'use strict';

    function basename() {
        var p = (global.location && global.location.pathname) || '';
        var i = p.lastIndexOf('/');
        return (i >= 0 ? p.slice(i + 1) : p) || '';
    }

    function normalizeRole(role) {
        var r = String(role || '').toLowerCase().replace(/-/g, '_');
        if (r === 'referees') return 'referee';
        if (r === 'referee_plus' || r === 'referees_plus') return 'referees_plus';
        return r;
    }

    var ROUTE_ACCESS = {
        'admin-dashboard.html': ['skf_admin', 'admin'],
        'player-dashboard.html': ['player'],
        'coach-dashboard.html': ['coach'],
        'club-dashboard.html': ['club_admin'],
        'referee-dashboard.html': ['referee', 'referees_plus'],
        'referee-tournaments.html': ['referee', 'referees_plus'],
        'referee-bracket.html': ['referee', 'referees_plus'],
        'referee-bracket-setup.html': ['referee', 'referees_plus'],
        'referee-match-control.html': ['referee', 'referees_plus'],
        'referee-match-history.html': ['referee', 'referees_plus'],
        'transfers.html': ['player', 'coach', 'club_admin', 'skf_admin', 'admin']
    };

    function parseUser() {
        try {
            var raw = global.localStorage.getItem('user');
            if (!raw) return null;
            return JSON.parse(raw);
        } catch (e) {
            return null;
        }
    }

    function dashboardForRole(role) {
        var r = normalizeRole(role);
        switch (r) {
            case 'skf_admin':
            case 'admin':
                return 'admin-dashboard.html';
            case 'player':
                return 'player-dashboard.html';
            case 'coach':
                return 'coach-dashboard.html';
            case 'club_admin':
                return 'club-dashboard.html';
            case 'referee':
            case 'referees_plus':
                return 'referee-dashboard.html';
            default:
                return 'index.html';
        }
    }

    function guardPage(opts) {
        var file = basename();
        var allow = (opts && opts.allow) || ROUTE_ACCESS[file];
        if (allow == null) return true;

        var tok = global.localStorage.getItem('token');
        var user = parseUser();
        if (!tok || !user) {
            if (allow.length) {
                if (global.location.protocol === 'file:') {
                    console.warn(
                        '[SKF] No auth token on this page. Opening the site via file:/// gives each .html file its own storage, '
                        + 'so login does not carry from referee-tournaments.html to referee-bracket.html. '
                        + 'Serve the html folder over http instead, e.g. cd html && python3 -m http.server 8080 '
                        + 'then open http://localhost:8080/referee-tournaments.html'
                    );
                }
                global.location.href = 'index.html';
            }
            return false;
        }

        var role = normalizeRole(user.role);
        if (!allow.length) return true;
        if (allow.indexOf(role) < 0) {
            global.location.href = dashboardForRole(user.role);
            return false;
        }
        return true;
    }

    function esc(s) {
        if (s == null) return '';
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function applyRefereeSidebar(active) {
        var user = parseUser();
        var role = normalizeRole(user && user.role);
        var isPlus = role === 'referees_plus';

        var hashOps = (global.location.hash || '').toLowerCase() === '#operations';
        var hashSetup = (global.location.hash || '').toLowerCase() === '#setup';
        if (basename() === 'referee-dashboard.html') {
            if (hashOps) active = 'operations';
            else if (hashSetup) active = 'setup';
        }

        var nav = global.document.getElementById('dashboardNav');
        if (!nav) return;
        var ul = nav.querySelector('ul.nav-menu');
        if (!ul) return;

        function item(href, label, key) {
            var on = (active === key) ? ' active' : '';
            return '<li class="nav-item"><a href="' + esc(href) + '" class="nav-link' + on + '">' + esc(label) + '</a></li>';
        }

        var rows = [];
        rows.push('<li class="nav-item"><a href="#" class="nav-link skf-nav-close" style="color:#ff4444;font-weight:bold;background-color:rgba(255,0,0,0.1);">&times; Close menu</a></li>');
        rows.push(item('referee-dashboard.html', 'Overview', 'dashboard'));
        rows.push(item('referee-dashboard.html#operations', 'Match operations', 'operations'));
        rows.push(item('referee-match-control.html', 'Match control', 'match-control'));
        if (isPlus) {
            rows.push(item('referee-dashboard.html#setup', 'Tournament setup (Referee+)', 'setup'));
            rows.push(item('referee-dashboard.html#belttest', 'Belt Tests (Examiner)', 'belttest'));
        }
        rows.push('<li class="nav-item" style="border-top:1px solid rgba(255,255,255,.1);margin-top:6px;padding-top:6px;"></li>');
        rows.push(item('referee-tournaments.html', 'Tournament list', 'tournaments'));
        rows.push(item('referee-bracket.html', 'Bracket view', 'bracket'));
        rows.push(item('referee-bracket-setup.html', 'Bracket setup', 'bracket-setup'));
        rows.push(item('referee-match-history.html', 'Match history', 'match-history'));
        rows.push('<li class="nav-item" style="border-top:1px solid rgba(255,255,255,.1);margin-top:6px;padding-top:6px;"></li>');
        rows.push(item('tournament.html', 'Public tournament list', 'public'));
        rows.push('<li class="nav-item"><a href="#" class="nav-link" onclick="logout();return false;">Logout</a></li>');

        ul.innerHTML = rows.join('');

        ul.querySelectorAll('.skf-nav-close').forEach(function (a) {
            a.addEventListener('click', function (e) {
                e.preventDefault();
                var mt = global.document.getElementById('menuToggle');
                var n = global.document.getElementById('dashboardNav');
                if (mt) mt.classList.remove('active');
                if (n) n.classList.remove('active');
            });
        });
    }

    function initRefereePage(activeKey) {
        if (!guardPage({ allow: ['referee', 'referees_plus'] })) return false;
        applyRefereeSidebar(activeKey || 'dashboard');
        return true;
    }

    function bindNavClose(ul) {
        if (!ul) return;
        ul.querySelectorAll('.skf-nav-close').forEach(function (a) {
            a.addEventListener('click', function (e) {
                e.preventDefault();
                var mt = global.document.getElementById('menuToggle');
                var n = global.document.getElementById('dashboardNav');
                if (mt) mt.classList.remove('active');
                if (n) n.classList.remove('active');
            });
        });
    }

    /** Player dashboard — sections: overview, events, matches, registrations, stats, rankings, profile */
    function applyPlayerSidebar(active) {
        var nav = global.document.getElementById('dashboardNav');
        if (!nav) return;
        var ul = nav.querySelector('ul.nav-menu');
        if (!ul) return;

        function sec(name, label, key) {
            var on = (active === key) ? ' active' : '';
            return '<li class="nav-item"><a href="#" class="nav-link' + on + '" onclick="showSection(\'' + name + '\',event);return false;">' + esc(label) + '</a></li>';
        }

        var rows = [];
        rows.push('<li class="nav-item"><a href="#" class="nav-link skf-nav-close" style="color:#ff4444;font-weight:bold;background-color:rgba(255,0,0,0.1);">&times; Close menu</a></li>');
        rows.push(sec('overview', 'Overview', 'overview'));
        rows.push('<li class="nav-item"><a href="transfers.html" class="nav-link">Transfers</a></li>');
        rows.push('<li class="nav-item"><a href="tournament.html" class="nav-link">Tournaments</a></li>');
        rows.push(sec('events', 'Upcoming events', 'events'));
        rows.push(sec('matches', 'Upcoming matches', 'matches'));
        rows.push(sec('registrations', 'My registrations', 'registrations'));
        rows.push(sec('stats', 'Stats', 'stats'));
        rows.push(sec('rankings', 'Rankings', 'rankings'));
        rows.push(sec('belttest', 'Belt Test', 'belttest'));
        rows.push('<li class="nav-item"><span class="nav-link" style="opacity:.55;cursor:default;font-size:13px;">Virtual exam — Coming soon</span></li>');
        rows.push('<li class="nav-item"><a href="#" id="navLinkProfile" class="nav-link' + (active === 'profile' ? ' active' : '') + '" onclick="showSection(\'profile\',event);return false;">Profile</a></li>');
        rows.push('<li class="nav-item"><a href="#" class="nav-link" onclick="logout();return false;">Logout</a></li>');

        ul.innerHTML = rows.join('');
        bindNavClose(ul);
    }

    function initPlayerPage(activeSection) {
        if (!guardPage({ allow: ['player'] })) return false;
        applyPlayerSidebar(activeSection || 'overview');
        return true;
    }

    /** Club admin — scroll sections via hash ids */
    function applyClubSidebar(active) {
        var nav = global.document.getElementById('dashboardNav');
        if (!nav) return;
        var ul = nav.querySelector('ul.nav-menu');
        if (!ul) return;

        function hash(h, label, key) {
            var on = (active === key) ? ' active' : '';
            return '<li class="nav-item"><a href="' + esc(h) + '" class="nav-link' + on + '" onclick="if(typeof closeClubMenu===\'function\')closeClubMenu();">' + esc(label) + '</a></li>';
        }

        var rows = [];
        rows.push('<li class="nav-item"><a href="#" class="nav-link skf-nav-close" style="color:#ff4444;font-weight:bold;background-color:rgba(255,0,0,0.1);">&times; Close menu</a></li>');
        rows.push(hash('#club-reg', 'Club registration', 'club-reg'));
        rows.push(hash('#players-mgmt', 'Players management', 'players-mgmt'));
        rows.push(hash('#players-ranking', 'Players ranking', 'players-ranking'));
        rows.push(hash('#players-op', 'Players & tournaments', 'players-op'));
        rows.push('<li class="nav-item"><a href="tournament.html" class="nav-link" onclick="if(typeof closeClubMenu===\'function\')closeClubMenu();">Tournaments</a></li>');
        rows.push('<li class="nav-item"><a href="transfers.html" class="nav-link" onclick="if(typeof closeClubMenu===\'function\')closeClubMenu();">Transfer market</a></li>');
        rows.push('<li class="nav-item"><a href="#" class="nav-link" onclick="logout();return false;">Logout</a></li>');

        ul.innerHTML = rows.join('');
        bindNavClose(ul);
    }

    function initClubPage(activeKey) {
        if (!guardPage({ allow: ['club_admin'] })) return false;
        applyClubSidebar(activeKey || 'club-reg');
        return true;
    }

    /** Coach dashboard — in-page sections */
    function applyCoachSidebar(active) {
        var nav = global.document.getElementById('dashboardNav');
        if (!nav) return;
        var ul = nav.querySelector('ul.nav-menu');
        if (!ul) return;

        function hash(h, label, key) {
            var on = (active === key) ? ' active' : '';
            return '<li class="nav-item"><a href="' + esc(h) + '" class="nav-link' + on + '">' + esc(label) + '</a></li>';
        }

        var rows = [];
        rows.push('<li class="nav-item"><a href="#" class="nav-link skf-nav-close" style="color:#ff4444;font-weight:bold;background-color:rgba(255,0,0,0.1);">&times; Close menu</a></li>');
        rows.push(hash('#coach-overview', 'Overview', 'coach-overview'));
        rows.push(hash('#profile', 'Profile', 'profile'));
        rows.push(hash('#player-management', 'Player management', 'player-management'));
        rows.push('<li class="nav-item"><a href="transfers.html" class="nav-link">Transfer market</a></li>');
        rows.push('<li class="nav-item"><a href="tournament.html" class="nav-link">Tournaments</a></li>');
        rows.push(hash('#live-matches', 'Live matches', 'live-matches'));
        rows.push('<li class="nav-item"><span class="nav-link" style="opacity:.55;cursor:default;font-size:13px;">Leaderboards — Coming soon</span></li>');
        rows.push('<li class="nav-item"><span class="nav-link" style="opacity:.55;cursor:default;font-size:13px;">Technical support — Coming soon</span></li>');
        rows.push('<li class="nav-item"><a href="#" class="nav-link" onclick="logout();return false;">Logout</a></li>');

        ul.innerHTML = rows.join('');
        bindNavClose(ul);
    }

    function initCoachPage(activeKey) {
        if (!guardPage({ allow: ['coach'] })) return false;
        applyCoachSidebar(activeKey || 'coach-overview');
        return true;
    }

    global.SKFRoleLayout = {
        normalizeRole: normalizeRole,
        guardPage: guardPage,
        dashboardForRole: dashboardForRole,
        applyRefereeSidebar: applyRefereeSidebar,
        initRefereePage: initRefereePage,
        applyPlayerSidebar: applyPlayerSidebar,
        initPlayerPage: initPlayerPage,
        applyClubSidebar: applyClubSidebar,
        initClubPage: initClubPage,
        applyCoachSidebar: applyCoachSidebar,
        initCoachPage: initCoachPage,
        ROUTE_ACCESS: ROUTE_ACCESS
    };
})(typeof window !== 'undefined' ? window : this);
