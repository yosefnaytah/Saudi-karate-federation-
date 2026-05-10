/**
 * SKF Highlights Banner — animated image carousel shown at the top of all dashboards.
 * Reads from skf_highlights table via direct REST (anon key) — no auth required.
 * Usage: SKFHighlights.init({ containerId: 'skf-hl', supabaseUrl: '...', anonKey: '...' });
 */
(function (global) {
    'use strict';

    var _opts    = null;
    var _items   = [];
    var _idx     = 0;
    var _cycle   = null;
    var _refresh = null;
    var _cssOk   = false;

    var SB_URL  = 'https://uqlpxdphikmmpdsuojil.supabase.co';
    var SB_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxbHB4ZHBoaWttbXBkc3VvamlsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTI5NDEsImV4cCI6MjA4NjM2ODk0MX0.03xQ8ltwZm_TTEAHDOHocfFKG2j_PHmL1Lzt2t-aFJU';

    // ── CSS ──────────────────────────────────────────────────────────────────
    function injectCss() {
        if (_cssOk) return;
        _cssOk = true;
        var s = document.createElement('style');
        s.textContent = [
            '.skf-hl{position:relative;width:100%;border-radius:14px;overflow:hidden;',
            'box-shadow:0 6px 28px rgba(0,0,0,.18);background:#1b5e20;margin-bottom:16px;}',
            '.skf-hl-slide{position:absolute;inset:0;opacity:0;transition:opacity .7s ease;pointer-events:none;}',
            '.skf-hl-slide.skf-active{opacity:1;pointer-events:auto;}',
            '.skf-hl-img{width:100%;height:100%;object-fit:cover;display:block;}',
            '.skf-hl-overlay{position:absolute;inset:0;',
            'background:linear-gradient(to bottom,rgba(0,0,0,.04) 0%,rgba(0,0,0,0) 40%,rgba(0,0,0,.72) 100%);}',
            '.skf-hl-text{position:absolute;bottom:0;left:0;right:0;padding:14px 22px 18px;color:#fff;}',
            '.skf-hl-tag{display:inline-block;background:#2e7d32;color:#fff;font-size:10px;font-weight:800;',
            'letter-spacing:.10em;text-transform:uppercase;padding:2px 10px;border-radius:999px;margin-bottom:7px;}',
            '.skf-hl-title{font-size:22px;font-weight:800;line-height:1.2;margin:0 0 4px;',
            'text-shadow:0 2px 6px rgba(0,0,0,.55);}',
            '.skf-hl-caption{font-size:13px;opacity:.9;margin:0;line-height:1.4;',
            'text-shadow:0 1px 3px rgba(0,0,0,.5);}',
            '.skf-hl-dots{position:absolute;bottom:12px;left:50%;transform:translateX(-50%);',
            'display:flex;gap:7px;align-items:center;}',
            '.skf-hl-dot{width:8px;height:8px;border-radius:50%;background:rgba(255,255,255,.45);',
            'border:none;cursor:pointer;padding:0;transition:background .3s,transform .3s;}',
            '.skf-hl-dot.skf-active{background:#fff;transform:scale(1.45);}',
            '.skf-hl-arrow{position:absolute;top:50%;transform:translateY(-50%);width:36px;height:36px;',
            'border-radius:50%;background:rgba(0,0,0,.32);border:none;color:#fff;font-size:20px;',
            'cursor:pointer;display:flex;align-items:center;justify-content:center;',
            'transition:background .2s;z-index:2;line-height:1;}',
            '.skf-hl-arrow:hover{background:rgba(0,0,0,.58);}',
            '.skf-hl-arrow.left{left:14px;}',
            '.skf-hl-arrow.right{right:14px;}'
        ].join('');
        document.head.appendChild(s);
    }

    function esc(s) {
        if (s == null) return '';
        return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }
    function escA(s) {
        if (s == null) return '';
        return String(s).replace(/"/g,'&quot;').replace(/'/g,'&#39;');
    }

    function getH() {
        var w = window.innerWidth || 800;
        if (w < 480) return 280;
        if (w < 768) return 380;
        if (w < 1200) return 460;
        return 520;
    }

    // ── Render ───────────────────────────────────────────────────────────────
    function render() {
        var el = document.getElementById(_opts && _opts.containerId);
        if (!el) return;
        if (!_items.length) { el.innerHTML = ''; return; }

        var h = getH();
        var slides = _items.map(function (item, i) {
            var src = String(item.image_url || '').trim();
            // If relative path, prepend Supabase storage base
            if (src && src.indexOf('http') !== 0) {
                src = SB_URL + '/storage/v1/object/public/' + src;
            }
            return '<div class="skf-hl-slide" data-hi="' + i + '">'
                + '<img class="skf-hl-img" src="' + escA(src) + '" alt="' + escA(item.title) + '" referrerpolicy="no-referrer">'
                + '<div class="skf-hl-overlay"></div>'
                + '<div class="skf-hl-text">'
                + '<div class="skf-hl-tag">SKF Highlights</div>'
                + '<p class="skf-hl-title">' + esc(item.title) + '</p>'
                + (item.caption ? '<p class="skf-hl-caption">' + esc(item.caption) + '</p>' : '')
                + '</div>'
                + '</div>';
        }).join('');

        var dots = _items.length > 1
            ? '<div class="skf-hl-dots">'
              + _items.map(function (_, i) {
                  return '<button class="skf-hl-dot" onclick="SKFHighlights._goTo(' + i + ')" aria-label="Slide ' + (i+1) + '"></button>';
              }).join('')
              + '</div>'
            : '';

        var arrows = _items.length > 1
            ? '<button class="skf-hl-arrow left"  onclick="SKFHighlights._prev()">&#8249;</button>'
            + '<button class="skf-hl-arrow right" onclick="SKFHighlights._next()">&#8250;</button>'
            : '';

        el.innerHTML = '<div class="skf-hl" style="height:' + h + 'px;">'
            + slides + dots + arrows + '</div>';

        _goTo(0);
    }

    function _goTo(idx) {
        _idx = ((idx % _items.length) + _items.length) % _items.length;
        var el = document.getElementById(_opts && _opts.containerId);
        if (!el) return;
        el.querySelectorAll('.skf-hl-slide').forEach(function (s, i) {
            s.classList.toggle('skf-active', i === _idx);
        });
        el.querySelectorAll('.skf-hl-dot').forEach(function (d, i) {
            d.classList.toggle('skf-active', i === _idx);
        });
    }

    function _next() { if (_items.length) { _goTo(_idx + 1); resetCycle(); } }
    function _prev() { if (_items.length) { _goTo(_idx - 1); resetCycle(); } }

    function startCycle() {
        if (_cycle) clearInterval(_cycle);
        if (_items.length <= 1) return;
        _cycle = setInterval(function () { _goTo(_idx + 1); }, 6000);
    }
    function resetCycle() { if (_cycle) clearInterval(_cycle); startCycle(); }

    // ── Data fetch via plain REST ────────────────────────────────────────────
    async function loadHighlights() {
        var url  = ((_opts && _opts.supabaseUrl) || SB_URL).replace(/\/$/, '');
        var anon = (_opts && _opts.anonKey) || SB_ANON;

        // ── Path 1: use the authenticated Supabase JS client when available ──
        var getSbFn = _opts && _opts.getSb;
        if (typeof getSbFn === 'function') {
            try {
                var sb = getSbFn();
                if (sb && sb.from) {
                    var q = await sb
                        .from('skf_highlights')
                        .select('id,title,caption,image_url,sort_order,created_at')
                        .eq('is_active', true)
                        .order('sort_order', { ascending: true })
                        .order('created_at', { ascending: false })
                        .limit(12);
                    if (!q.error) {
                        _items = Array.isArray(q.data) ? q.data : [];
                        console.log('[SKFHighlights] ' + _items.length + ' highlight(s) loaded via client');
                        render();
                        startCycle();
                        return;
                    }
                    console.warn('[SKFHighlights] client error:', q.error.message, '— falling back to REST');
                }
            } catch (e) {
                console.warn('[SKFHighlights] client threw:', e, '— falling back to REST');
            }
        }

        // ── Path 2: direct REST fetch with user JWT from localStorage ──
        var token = '';
        try { token = localStorage.getItem('token') || ''; } catch (e) {}
        if (!token || token.indexOf('local-token') === 0) token = anon;

        try {
            var endpoint = url
                + '/rest/v1/skf_highlights'
                + '?is_active=eq.true'
                + '&select=id,title,caption,image_url,sort_order,created_at'
                + '&order=sort_order.asc,created_at.desc'
                + '&limit=12';

            var resp = await fetch(endpoint, {
                headers: {
                    'apikey': anon,
                    'Authorization': 'Bearer ' + token,
                    'Accept': 'application/json'
                }
            });

            if (!resp.ok) {
                console.warn('[SKFHighlights] HTTP ' + resp.status + ' — run database/phase23_highlights.sql in Supabase if table is missing');
                return;
            }

            var data = await resp.json();
            _items = Array.isArray(data) ? data : [];
            console.log('[SKFHighlights] ' + _items.length + ' highlight(s) loaded via REST');
            render();
            startCycle();

        } catch (e) {
            console.warn('[SKFHighlights] fetch error:', e);
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────
    function init(opts) {
        _opts = opts || {};
        injectCss();
        if (_refresh) clearInterval(_refresh);
        loadHighlights();
        _refresh = setInterval(loadHighlights, 60000);
    }

    global.SKFHighlights = {
        init: init,
        _goTo: _goTo,
        _next: _next,
        _prev: _prev,
        reload: loadHighlights
    };

})(typeof window !== 'undefined' ? window : this);
