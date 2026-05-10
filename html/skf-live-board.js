/**
 * SKF Live Match Board — animated widget for all dashboards.
 * Usage:
 *   SKFLiveBoard.init({ containerId: 'skf-lb', getSb: function(){ return supabaseClient; }, supabaseUrl: '...' });
 */
(function (global) {
    'use strict';

    var _opts = null;
    var _matches = [];
    var _idx = 0;
    var _cycleTimer = null;
    var _refreshTimer = null;
    var _rtSub = null;
    var _cssInjected = false;
    var _debounce = null;

    function injectCss() {
        if (_cssInjected) return;
        _cssInjected = true;
        var s = document.createElement('style');
        s.textContent = [
            '.skf-lb{background:#fff;border-radius:14px;box-shadow:0 4px 24px rgba(0,0,0,.10);overflow:hidden;font-family:inherit;}',
            '.skf-lb-hdr{background:linear-gradient(135deg,#1b5e20,#388e3c);padding:10px 16px;display:flex;align-items:center;justify-content:space-between;}',
            '.skf-lb-hdr-title{color:#fff;font-size:13px;font-weight:800;letter-spacing:.07em;text-transform:uppercase;}',
            '.skf-lb-hdr-live{display:flex;align-items:center;gap:6px;font-size:11px;color:rgba(255,255,255,.85);font-weight:600;}',
            '.skf-lb-hdr-dot{width:8px;height:8px;border-radius:50%;background:#69f0ae;animation:skfLbPulse 1.4s infinite;}',
            '@keyframes skfLbPulse{0%,100%{opacity:1;transform:scale(1);}50%{opacity:.5;transform:scale(.82);}}',
            '.skf-lb-viewport{position:relative;height:160px;overflow:hidden;background:#fafafa;}',
            '.skf-lb-card{position:absolute;inset:0;display:flex;align-items:center;padding:12px 24px;gap:16px;',
            'opacity:0;transform:translateX(30px);transition:opacity .45s ease,transform .45s ease;pointer-events:none;}',
            '.skf-lb-card.skf-active{opacity:1;transform:translateX(0);pointer-events:auto;}',
            '.skf-lb-card.skf-exit{opacity:0;transform:translateX(-30px);}',
            '.skf-lb-side{display:flex;flex-direction:column;align-items:center;gap:7px;flex:1;min-width:0;}',
            '.skf-lb-photo{width:60px;height:60px;border-radius:50%;object-fit:cover;flex-shrink:0;border:3px solid;}',
            '.skf-lb-photo.red{border-color:#e53935;}',
            '.skf-lb-photo.blue{border-color:#1565c0;}',
            '.skf-lb-init{width:60px;height:60px;border-radius:50%;display:flex;align-items:center;justify-content:center;',
            'font-size:22px;font-weight:800;flex-shrink:0;border:3px solid;}',
            '.skf-lb-init.red{border-color:#e53935;background:#ffebee;color:#e53935;}',
            '.skf-lb-init.blue{border-color:#1565c0;background:#e3f2fd;color:#1565c0;}',
            '.skf-lb-name{font-size:12px;font-weight:700;color:#1b1b1b;text-align:center;',
            'white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:110px;}',
            '.skf-lb-score{font-size:42px;font-weight:900;line-height:1;flex-shrink:0;}',
            '.skf-lb-score.red{color:#e53935;}',
            '.skf-lb-score.blue{color:#1565c0;}',
            '.skf-lb-centre{display:flex;flex-direction:column;align-items:center;gap:5px;flex-shrink:0;}',
            '.skf-lb-badge{padding:3px 10px;border-radius:999px;font-size:10px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;}',
            '.skf-lb-badge.live{background:#e53935;color:#fff;animation:skfLbPulse 1.4s infinite;}',
            '.skf-lb-badge.upcoming{background:#e8f5e9;color:#2e7d32;}',
            '.skf-lb-badge.done{background:#f5f5f5;color:#666;}',
            '.skf-lb-vs{font-size:18px;font-weight:900;color:#ccc;}',
            '.skf-lb-round{font-size:10px;color:#aaa;font-weight:600;letter-spacing:.04em;text-align:center;max-width:80px;}',
            '.skf-lb-footer{display:flex;align-items:center;justify-content:space-between;padding:7px 14px;background:#f5f5f5;border-top:1px solid #ebebeb;}',
            '.skf-lb-dots{display:flex;gap:5px;align-items:center;}',
            '.skf-lb-dot-btn{width:7px;height:7px;border-radius:50%;background:#ddd;',
            'transition:background .3s,transform .3s;cursor:pointer;border:none;padding:0;}',
            '.skf-lb-dot-btn.skf-active{background:#2e7d32;transform:scale(1.35);}',
            '.skf-lb-nav{display:flex;gap:4px;}',
            '.skf-lb-nav-btn{width:24px;height:24px;border:1px solid #e0e0e0;border-radius:50%;',
            'background:#fff;cursor:pointer;font-size:14px;display:flex;align-items:center;justify-content:center;color:#555;line-height:1;}',
            '.skf-lb-nav-btn:hover{background:#e8f5e9;border-color:#a5d6a7;}',
            '.skf-lb-count{font-size:11px;color:#888;}',
            '.skf-lb-empty{display:flex;align-items:center;justify-content:center;height:100%;color:#aaa;font-size:13px;}'
        ].join('');
        document.head.appendChild(s);
    }

    function esc(s) {
        if (s == null) return '';
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }
    function escA(s) {
        if (s == null) return '';
        return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;');
    }

    function resolvePhoto(raw) {
        if (!raw) return '';
        var u = String(raw).trim();
        if (!u) return '';
        if (u.indexOf('http://') === 0 || u.indexOf('https://') === 0) return u;
        var base = ((_opts && _opts.supabaseUrl) || '').replace(/\/$/, '');
        if (!base) return u;
        if (u.indexOf('/storage/') === 0) return base + u;
        return base + '/storage/v1/object/public/' + u;
    }

    function photoEl(photoUrl, name, side) {
        var init = name ? String(name).charAt(0).toUpperCase() : '?';
        var safeInit = esc(init);
        var safeSide = side === 'red' ? 'red' : 'blue';
        if (photoUrl) {
            var fallback = 'this.outerHTML=\'<div class="skf-lb-init ' + safeSide + '">' + safeInit + '</div>\'';
            return '<img class="skf-lb-photo ' + safeSide + '" src="' + escA(photoUrl) + '" alt="" referrerpolicy="no-referrer" onerror="' + escA(fallback) + '">';
        }
        return '<div class="skf-lb-init ' + safeSide + '">' + safeInit + '</div>';
    }

    function roundLabel(rn) {
        var n = parseInt(rn, 10);
        if (isNaN(n)) return '';
        if (n >= 90) return 'Final';
        if (n >= 80) return 'Semi-Final';
        if (n >= 70) return 'Quarter-Final';
        return 'Round ' + n;
    }

    function buildCard(m, idx) {
        var st = String(m.status || '').toLowerCase();
        var isLive = st === 'live';
        var isDone = st === 'completed';
        var showScores = isLive || isDone;
        var badgeClass = isLive ? 'live' : isDone ? 'done' : 'upcoming';
        var badgeText = isLive ? 'LIVE' : isDone ? 'ENDED' : 'UPCOMING';
        var rLabel = roundLabel(m.round_number);
        var rName = m._redName || (m.red_user_id ? 'Red' : 'TBD');
        var bName = m._blueName || (m.blue_user_id ? 'Blue' : 'TBD');
        var rPhoto = resolvePhoto(m._redPhoto);
        var bPhoto = resolvePhoto(m._bluePhoto);
        var rScore = m.red_score != null ? esc(String(m.red_score)) : '0';
        var bScore = m.blue_score != null ? esc(String(m.blue_score)) : '0';

        return '<div class="skf-lb-card" data-lb-idx="' + idx + '">'
            + '<div class="skf-lb-side">'
            + photoEl(rPhoto, rName, 'red')
            + '<div class="skf-lb-name">' + esc(rName) + '</div>'
            + '</div>'
            + (showScores ? '<div class="skf-lb-score red">' + rScore + '</div>' : '')
            + '<div class="skf-lb-centre">'
            + '<span class="skf-lb-badge ' + badgeClass + '">' + badgeText + '</span>'
            + '<span class="skf-lb-vs">VS</span>'
            + '<span class="skf-lb-round">' + esc(rLabel) + '</span>'
            + '</div>'
            + (showScores ? '<div class="skf-lb-score blue">' + bScore + '</div>' : '')
            + '<div class="skf-lb-side">'
            + photoEl(bPhoto, bName, 'blue')
            + '<div class="skf-lb-name">' + esc(bName) + '</div>'
            + '</div>'
            + '</div>';
    }

    function getContainer() {
        return _opts ? document.getElementById(_opts.containerId) : null;
    }

    function render() {
        var el = getContainer();
        if (!el) return;
        var cid = _opts.containerId;

        if (!_matches.length) {
            el.innerHTML = '<div class="skf-lb">'
                + '<div class="skf-lb-hdr"><span class="skf-lb-hdr-title">Match Board</span>'
                + '<div class="skf-lb-hdr-live"><div class="skf-lb-hdr-dot"></div>Live</div></div>'
                + '<div class="skf-lb-viewport"><div class="skf-lb-empty">No live or upcoming matches right now</div></div>'
                + '<div class="skf-lb-footer"><div class="skf-lb-dots"></div><span></span><div class="skf-lb-nav"></div></div>'
                + '</div>';
            return;
        }

        var cards = _matches.map(function (m, i) { return buildCard(m, i); }).join('');
        var dots = _matches.map(function (_, i) {
            return '<button class="skf-lb-dot-btn" data-lb-dot="' + i + '" onclick="SKFLiveBoard._goTo(' + i + ')" aria-label="Match ' + (i + 1) + '"></button>';
        }).join('');

        el.innerHTML = '<div class="skf-lb">'
            + '<div class="skf-lb-hdr">'
            + '<span class="skf-lb-hdr-title">Match Board</span>'
            + '<div class="skf-lb-hdr-live"><div class="skf-lb-hdr-dot"></div>Live Updates</div>'
            + '</div>'
            + '<div class="skf-lb-viewport">' + cards + '</div>'
            + '<div class="skf-lb-footer">'
            + '<div class="skf-lb-dots">' + dots + '</div>'
            + '<span class="skf-lb-count" id="skfLbCount_' + cid + '"></span>'
            + '<div class="skf-lb-nav">'
            + '<button class="skf-lb-nav-btn" onclick="SKFLiveBoard._prev()" title="Previous">&#8249;</button>'
            + '<button class="skf-lb-nav-btn" onclick="SKFLiveBoard._next()" title="Next">&#8250;</button>'
            + '</div>'
            + '</div>'
            + '</div>';

        _goTo(Math.min(_idx, _matches.length - 1), true);
    }

    function _goTo(idx, immediate) {
        if (!_matches.length) return;
        _idx = (idx + _matches.length) % _matches.length;
        var el = getContainer();
        if (!el) return;

        var cards = el.querySelectorAll('.skf-lb-card');
        var dots = el.querySelectorAll('.skf-lb-dot-btn');

        cards.forEach(function (c, i) {
            c.classList.remove('skf-active', 'skf-exit');
            if (i === _idx) c.classList.add('skf-active');
        });
        dots.forEach(function (d, i) {
            d.classList.toggle('skf-active', i === _idx);
        });

        var cnt = el.querySelector('.skf-lb-count');
        if (cnt) cnt.textContent = (_idx + 1) + ' / ' + _matches.length;
    }

    function _next() {
        if (!_matches.length) return;
        _goTo(_idx + 1);
    }

    function _prev() {
        if (!_matches.length) return;
        _goTo(_idx - 1);
    }

    function startCycle() {
        stopCycle();
        if (_matches.length <= 1) return;
        _cycleTimer = setInterval(_next, 4500);
    }

    function stopCycle() {
        if (_cycleTimer) { clearInterval(_cycleTimer); _cycleTimer = null; }
    }

    function stopRefresh() {
        if (_refreshTimer) { clearInterval(_refreshTimer); _refreshTimer = null; }
        if (_debounce) { clearTimeout(_debounce); _debounce = null; }
    }

    function subscribeRealtime(tournamentIds) {
        if (!_opts || !_opts.getSb) return;
        if (!tournamentIds || !tournamentIds.length) return;
        if (typeof SKFMatchRealtime === 'undefined') return;
        var sb = _opts.getSb();
        if (!sb) return;
        try {
            if (_rtSub) { try { _rtSub.unsubscribe(); } catch (e) {} _rtSub = null; }
            _rtSub = SKFMatchRealtime.subscribeTournamentsMatches(sb, tournamentIds, function () {
                clearTimeout(_debounce);
                _debounce = setTimeout(loadMatches, 600);
            });
        } catch (e) { console.warn('[SKFLiveBoard] realtime:', e); }
    }

    async function loadMatches() {
        if (!_opts || !_opts.getSb) return;
        var sb = _opts.getSb();
        if (!sb) return;
        try {
            var mq = await sb.from('tournament_matches')
                .select('id,round_number,bracket_position,status,red_user_id,blue_user_id,red_score,blue_score,winner_user_id,tournament_id,category_id')
                .in('status', ['live', 'scheduled', 'completed'])
                .order('round_number', { ascending: false })
                .limit(24);

            if (mq.error || !mq.data) return;

            // Sort: live first, then scheduled, then completed (recently updated)
            var order = { live: 0, scheduled: 1, completed: 2 };
            var rows = mq.data.slice().sort(function (a, b) {
                return (order[a.status] || 9) - (order[b.status] || 9);
            });

            // Only include completed if fewer than 3 live/scheduled matches
            var activeCnt = rows.filter(function (r) { return r.status !== 'completed'; }).length;
            if (activeCnt >= 3) {
                rows = rows.filter(function (r) { return r.status !== 'completed'; });
            }
            rows = rows.slice(0, 8);

            // Collect all user IDs
            var ids = [];
            rows.forEach(function (m) {
                if (m.red_user_id && ids.indexOf(m.red_user_id) < 0) ids.push(m.red_user_id);
                if (m.blue_user_id && ids.indexOf(m.blue_user_id) < 0) ids.push(m.blue_user_id);
            });

            var umap = {};
            var pmap = {};

            if (ids.length) {
                var uq = await sb.from('users').select('id,full_name,email').in('id', ids);
                if (!uq.error && uq.data) {
                    uq.data.forEach(function (u) {
                        umap[String(u.id)] = (u.full_name && String(u.full_name).trim()) || (u.email && String(u.email).trim()) || 'Athlete';
                    });
                }
                // Photos from profiles
                var aq = await sb.from('profiles').select('user_id,avatar_url').in('user_id', ids);
                if (!aq.error && aq.data) {
                    aq.data.forEach(function (p) { if (p.avatar_url) pmap[String(p.user_id)] = p.avatar_url; });
                }
                // Photos from bracket RPC (SECURITY DEFINER — gets more results)
                try {
                    var rpc = await sb.rpc('bracket_setup_fetch_avatars', { p_user_ids: ids });
                    if (!rpc.error && rpc.data) {
                        var list = Array.isArray(rpc.data) ? rpc.data : [rpc.data];
                        list.forEach(function (r) {
                            if (r && r.user_id && r.avatar_url) pmap[String(r.user_id)] = r.avatar_url;
                        });
                    }
                } catch (e) { /* phase12 RPC may not exist on all installs */ }
            }

            rows.forEach(function (m) {
                m._redName = m.red_user_id ? (umap[String(m.red_user_id)] || null) : null;
                m._blueName = m.blue_user_id ? (umap[String(m.blue_user_id)] || null) : null;
                m._redPhoto = m.red_user_id ? (pmap[String(m.red_user_id)] || null) : null;
                m._bluePhoto = m.blue_user_id ? (pmap[String(m.blue_user_id)] || null) : null;
            });

            _matches = rows;
            _idx = 0;
            render();
            startCycle();

            // Subscribe to all found tournament IDs
            var tids = [];
            rows.forEach(function (m) {
                if (m.tournament_id && tids.indexOf(m.tournament_id) < 0) tids.push(m.tournament_id);
            });
            if (tids.length) subscribeRealtime(tids);

        } catch (e) {
            console.warn('[SKFLiveBoard] loadMatches:', e);
        }
    }

    function init(opts) {
        _opts = opts;
        injectCss();

        stopCycle();
        stopRefresh();

        loadMatches();

        // Periodic refresh every 30 s
        _refreshTimer = setInterval(loadMatches, 30000);
    }

    global.SKFLiveBoard = {
        init: init,
        _goTo: _goTo,
        _next: _next,
        _prev: _prev,
        reload: loadMatches
    };

})(typeof window !== 'undefined' ? window : this);
