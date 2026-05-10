/**
 * SKF Bracket Engine v2 — Professional knockout bracket renderer
 * Shared between referee-bracket-setup.html (editable) and referee-bracket.html (view-only)
 * 2026-05-04
 *
 * Spacing math (all values in px):
 *   H          = match card height (must match CSS .bks-match min-height)
 *   G          = base gap in round-0
 *   pitch(ri)  = 2^ri * (H+G)          — distance between match card tops in round ri
 *   ptop(ri)   = (2^ri-1)/2 * (H+G)    — padding-top of first match in round ri
 *   mbот(ri)   = pitch(ri) - H          — margin-bottom between matches in round ri
 *
 * These ensure every match in round ri+1 is vertically centred between its
 * feeder pair in round ri.
 */
(function (W) {
    'use strict';

    // Geometry — keep in sync with CSS
    var H        = 130;  // match card height
    var G        = 16;   // base gap (round-0)
    var CONN_GAP = 40;   // horizontal space between round columns (margin-right)
    var HALF_GAP = 20;   // CONN_GAP / 2
    var HALF_H   = 65;   // H / 2

    function esc(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g,'&amp;').replace(/</g,'&lt;')
            .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
    }

    /**
     * Resolve a raw DB value (full https URL or a relative storage path) to a
     * usable <img src> value. Reads the Supabase project URL from the host page's
     * global variables (RBS_SB_URL or RB_SB_URL) — no config needed here.
     */
    function resolveImgUrl(raw) {
        if (!raw) return null;
        var u = String(raw).trim();
        if (!u) return null;
        var base = (
            (typeof RBS_SB_URL !== 'undefined' && RBS_SB_URL) ||
            (typeof RB_SB_URL  !== 'undefined' && RB_SB_URL)  ||
            (W.SKF_SUPABASE_URL ? W.SKF_SUPABASE_URL : '') ||
            ''
        ).replace(/\/$/, '');
        if (typeof W.skfResolveAvatarUrl === 'function') {
            var r = W.skfResolveAvatarUrl(u, base || undefined);
            if (r) return r;
        }
        if (/^https?:\/\//i.test(u)) return u;
        if (/^data:/i.test(u) || /^blob:/i.test(u)) return u;
        if (!base) return u;
        var p = u.replace(/^\//, '');
        if (p.indexOf('storage/v1') === 0) return base + '/' + p;
        return base + '/storage/v1/object/public/' + p;
    }

    function roundLabel(ri, total) {
        var rem = total - ri;
        if (total === 1) return 'Final';
        if (rem === 1)   return 'Final';
        // Semi-final / Quarter-final labels only when there are rounds before them
        if (rem === 2 && total > 2) return 'Semi-final';
        if (rem === 3 && total > 3) return 'Quarter-final';
        return 'Round ' + (ri + 1);
    }

    function ptop(ri)  { return (Math.pow(2,ri)-1)/2*(H+G); }
    function mbot(ri)  { return Math.pow(2,ri)*(H+G)-H; }

    function avatar(player, size, side) {
        size = size || 36;
        var palette = {
            red  :{ ring:'#ef5350', bg:'#ffebee', fg:'#ef5350' },
            blue :{ ring:'#1e88e5', bg:'#e3f2fd', fg:'#1e88e5' },
            win  :{ ring:'#2e7d32', bg:'#e8f5e9', fg:'#2e7d32' },
            grey :{ ring:'#bdbdbd', bg:'#f5f5f5', fg:'#9e9e9e' }
        };
        var c = palette[side] || palette.grey;
        var st = 'width:'+size+'px;height:'+size+'px;border-radius:50%;flex-shrink:0;'
               + 'display:flex;align-items:center;justify-content:center;'
               + 'border:2px solid '+c.ring+';background:'+c.bg+';overflow:hidden;'
               + 'font-size:'+Math.floor(size*0.36)+'px;font-weight:700;color:'+c.fg+';';
        var rawUrl = player && (player.profile_image_url || player.profile_photo_url || player.avatar_url);
        var url    = rawUrl ? resolveImgUrl(rawUrl) : null;
        var ini    = initials(player) || '?';
        if (url) {
            return '<div style="'+st+'">'
                 + '<img src="'+esc(url)+'" style="width:100%;height:100%;object-fit:cover;" alt=""'
                 + ' onerror="this.parentNode.textContent=\''+esc(ini)+'\';this.remove();">'
                 + '</div>';
        }
        return '<div style="'+st+'">'+esc(ini)+'</div>';
    }

    function initials(p) {
        if (!p || !p.full_name) return '';
        return p.full_name.split(/\s+/).filter(Boolean)
            .map(function(w){ return w.charAt(0).toUpperCase(); }).slice(0,2).join('');
    }

    function displayName(p) {
        if (!p) return null;
        return (p.full_name && p.full_name.trim()) || (p.email && p.email.trim()) || null;
    }

    // ── Setup slot ──────────────────────────────────────────────────────────
    function setupSlot(s, rn, mn, sn, player) {
        var side      = sn === 1 ? 'red'    : 'blue';
        var clr       = sn === 1 ? '#ef5350': '#1e88e5';
        var bg        = sn === 1 ? '#fff8f8': '#f5f9ff';
        var lbl       = sn === 1 ? 'RED'    : 'BLUE';
        var onClick   = 'openPickerForSlot('+rn+','+mn+','+sn+')';
        var onRemove  = 'event.stopPropagation();removeFromSlot('+rn+','+mn+','+sn+')';
        var filled    = player || (s&&s.playerId) || (s&&s.manualName&&s.manualName.trim());
        var bgStyle   = filled ? 'background:'+bg+';' : '';
        var h = '<div class="bks-slot bks-'+side+'" style="'+bgStyle+'" onclick="'+onClick+'">'
              + '<span class="bks-side-badge" style="background:'+clr+';">'+lbl+'</span>';
        if (player) {
            h += avatar(player,36,side)
              + '<div class="bks-slot-info">'
              + '<div class="bks-slot-name">'+esc(player.full_name||'Participant')+'</div>'
              + '<div class="bks-slot-club">'+esc(player.club_name||'')+'</div>'
              + '</div>'
              + '<button class="bks-slot-del" onclick="'+onRemove+'" title="Remove">&times;</button>';
        } else if (s && s.playerId) {
            h += avatar(null,36,'grey')
              + '<div class="bks-slot-info"><div class="bks-slot-name bks-muted">Participant</div></div>'
              + '<button class="bks-slot-del" onclick="'+onRemove+'" title="Remove">&times;</button>';
        } else if (s && s.manualName && s.manualName.trim()) {
            h += avatar(null,36,'grey')
              + '<div class="bks-slot-info"><div class="bks-slot-name">'+esc(s.manualName.trim())
              + ' <span class="bks-prov-tag">provisional</span></div></div>'
              + '<button class="bks-slot-del" onclick="'+onRemove+'" title="Remove">&times;</button>';
        } else {
            h += '<span class="bks-assign-label">+ Assign player</span>';
        }
        h += '</div>';
        return h;
    }

    // ── View slot ───────────────────────────────────────────────────────────
    function viewSlot(player, uid, score, isWin, side) {
        var clr  = side==='red' ? '#ef5350':'#1e88e5';
        var bg   = side==='red' ? '#fff8f8':'#f5f9ff';
        var lbl  = side==='red' ? 'RED'    :'BLUE';
        var name = displayName(player) || (uid ? 'Participant' : null);
        var avSide = isWin ? 'win' : (uid ? side : 'grey');
        var slotBg = isWin ? '#f0fff4' : (uid ? bg : '#fafafa');
        var h = '<div class="bks-slot bks-'+side+(isWin?' bks-winner-slot':'')+'" style="background:'+slotBg+';">'
              + '<span class="bks-side-badge" style="background:'+(isWin?'#2e7d32':clr)+';">'
              + (isWin?'WIN':lbl)+'</span>';
        if (!uid) {
            h += '<div class="bks-slot-info"><div class="bks-slot-name bks-muted" style="font-style:italic;">TBD</div></div>';
        } else {
            h += avatar(player,36,avSide)
               + '<div class="bks-slot-info">'
               + '<div class="bks-slot-name">'+esc(name||'Participant')+'</div>'
               + '<div class="bks-slot-club">'+esc(player?(player.club_name||''):'')+'</div>'
               + '</div>';
        }
        h += '<div class="bks-score'+(isWin?' bks-score-win':'')+'">'+((score!=null&&score!=='')?score:'')+'</div>';
        h += '</div>';
        return h;
    }

    // ── Match card ──────────────────────────────────────────────────────────
    function card(hdr, s1, s2, extraCls, styleStr, clickAttr, isLast, isFirstRound) {
        var stubR = isLast ? '' : '<div class="bks-stub-r"></div>';
        var stubL = isFirstRound ? '' : '<div class="bks-stub-l"></div>';
        return '<div class="bks-match '+(extraCls||'')+'" '
             + (styleStr?'style="'+styleStr+'"':'')
             + (clickAttr||'') + '>'
             + stubL + stubR
             + hdr + s1
             + '<div class="bks-slot-divider"></div>'
             + s2 + '</div>';
    }

    // ── SETUP renderer ──────────────────────────────────────────────────────
    function renderSetup(slots, findPlayerFn) {
        if (!slots || !slots.length) {
            return '<div class="bks-empty">'
                 + 'No bracket generated yet.<br>'
                 + '<span style="font-size:12px;color:#bbb;">Use Auto Seed or Generate Bracket above.</span>'
                 + '</div>';
        }

        var rounds = {};
        slots.forEach(function(s) {
            if (!rounds[s.round]) rounds[s.round] = {};
            if (!rounds[s.round][s.match]) rounds[s.round][s.match] = {s1:null,s2:null,matchId:s.matchId};
            if (s.slot===1) rounds[s.round][s.match].s1 = s;
            else            rounds[s.round][s.match].s2 = s;
        });

        var rKeys   = Object.keys(rounds).map(Number).sort(function(a,b){return a-b;});
        var nRounds = rKeys.length;
        var html    = '<div class="bks-bracket">';

        rKeys.forEach(function(r, ri) {
            var mKeys  = Object.keys(rounds[r]).map(Number).sort(function(a,b){return a-b;});
            var lbl    = roundLabel(ri, nRounds);
            var isFirst= ri===0;
            var isLast = ri===nRounds-1;
            var pt     = Math.round(ptop(ri));

            html += '<div class="bks-round'+(isLast?' bks-round-last':'')+'">';
            html += '<div class="bks-round-label">'
                 + '<span class="bks-round-name">'+esc(lbl)+'</span>'
                 + '<span class="bks-round-count">'+mKeys.length+' match'+(mKeys.length>1?'es':'')+'</span>'
                 + '</div>';
            html += '<div class="bks-round-body" style="padding-top:'+pt+'px;">';

            mKeys.forEach(function(m, mi) {
                var box  = rounds[r][m];
                var p1   = box.s1&&box.s1.playerId ? findPlayerFn(box.s1.playerId) : null;
                var p2   = box.s2&&box.s2.playerId ? findPlayerFn(box.s2.playerId) : null;
                var hasp = (p1||(box.s1&&(box.s1.playerId||(box.s1.manualName&&box.s1.manualName.trim()))))
                        && (p2||(box.s2&&(box.s2.playerId||(box.s2.manualName&&box.s2.manualName.trim()))));
                var mb   = mi<mKeys.length-1 ? Math.round(mbot(ri)) : 0;
                var hdr  = '<div class="bks-match-hdr">Match '+m+'</div>';

                html += card(hdr, setupSlot(box.s1,r,m,1,p1), setupSlot(box.s2,r,m,2,p2),
                         hasp?'bks-match-ready':'', 'margin-bottom:'+mb+'px;', '', isLast, isFirst);

                if (mi < mKeys.length-1) {
                    var connH = Math.round(mbot(ri));
                    if (mi%2===0) {
                        html += '<div class="bks-conn-v" style="height:'+connH+'px;"></div>';
                    } else {
                        html += '<div style="height:'+connH+'px;"></div>';
                    }
                }
            });

            html += '</div></div>';
        });

        html += '</div>';
        return html;
    }

    // ── VIEW renderer ───────────────────────────────────────────────────────
    function renderView(matches, getPlayerFn) {
        if (!matches || !matches.length) {
            return '<div class="bks-empty">No matches found for this bracket.</div>';
        }

        var rounds = {};
        matches.forEach(function(m) {
            var r = m.round_number || 1;
            if (!rounds[r]) rounds[r] = [];
            rounds[r].push(m);
        });

        var rKeys   = Object.keys(rounds).map(Number).sort(function(a,b){return a-b;});
        var nRounds = rKeys.length;
        var html    = '<div class="bks-bracket">';

        rKeys.forEach(function(r, ri) {
            var ms = rounds[r].slice().sort(function(a,b){
                return (a.bracket_position||0)-(b.bracket_position||0);
            });
            var lbl    = roundLabel(ri, nRounds);
            var isFirst= ri===0;
            var isLast = ri===nRounds-1;
            var pt     = Math.round(ptop(ri));

            html += '<div class="bks-round'+(isLast?' bks-round-last':'')+'">';
            html += '<div class="bks-round-label">'
                 + '<span class="bks-round-name">'+esc(lbl)+'</span>'
                 + '<span class="bks-round-count">'+ms.length+' match'+(ms.length>1?'es':'')+'</span>'
                 + '</div>';
            html += '<div class="bks-round-body" style="padding-top:'+pt+'px;">';

            ms.forEach(function(m, mi) {
                var p1    = m.red_user_id  ? getPlayerFn(m.red_user_id)  : null;
                var p2    = m.blue_user_id ? getPlayerFn(m.blue_user_id) : null;
                var p1Win = !!(m.winner_user_id&&String(m.winner_user_id)===String(m.red_user_id));
                var p2Win = !!(m.winner_user_id&&String(m.winner_user_id)===String(m.blue_user_id));
                var isLive= m.status==='live'||m.status==='in_progress';
                var isDone= m.status==='completed';
                var mb    = mi<ms.length-1 ? Math.round(mbot(ri)) : 0;
                var cls   = (isDone?'bks-match-done ':'')+(isLive?'bks-match-live ':'')
                          + (m.red_user_id&&m.blue_user_id?'bks-match-ready':'');
                var livePill = isLive ? '<div class="bks-live-pill">LIVE</div>' : '';
                var hdrCls  = isDone ? 'bks-match-hdr bks-hdr-done':'bks-match-hdr';
                var hdr     = livePill+'<div class="'+hdrCls+'">Match '+esc(String(m.bracket_position||''))
                            + (isDone?' &mdash; Complete':'')+'</div>';

                html += card(hdr, viewSlot(p1,m.red_user_id,m.red_score,p1Win,'red'),
                         viewSlot(p2,m.blue_user_id,m.blue_score,p2Win,'blue'),
                         cls.trim(), 'margin-bottom:'+mb+'px;cursor:pointer;',
                         'onclick="onMatchClick(\''+esc(m.id)+'\')"', isLast, isFirst);

                if (mi < ms.length-1) {
                    var connH = Math.round(mbot(ri));
                    if (mi%2===0) {
                        html += '<div class="bks-conn-v" style="height:'+connH+'px;"></div>';
                    } else {
                        html += '<div style="height:'+connH+'px;"></div>';
                    }
                }
            });

            html += '</div></div>';
        });

        html += '</div>';
        return html;
    }

    // ── CSS ─────────────────────────────────────────────────────────────────
    var CSS = '.bks-bracket{display:flex;align-items:flex-start;gap:0;overflow-x:auto;padding:24px 8px 56px;min-height:320px;}'
    + '.bks-round{display:flex;flex-direction:column;flex-shrink:0;width:255px;margin-right:40px;}'
    + '.bks-round-last{margin-right:0;}'
    + '.bks-round-label{display:flex;align-items:baseline;gap:8px;padding:0 0 14px;border-bottom:2px solid #e8f5e9;margin-bottom:4px;}'
    + '.bks-round-name{font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.1em;color:#1b5e20;}'
    + '.bks-round-count{font-size:10px;color:#b0bec5;font-weight:600;}'
    + '.bks-round-body{display:flex;flex-direction:column;position:relative;}'
    + '.bks-match{background:#fff;border-radius:10px;border:1.5px solid #e0e0e0;'
    +   'position:relative;overflow:visible;transition:box-shadow .2s,border-color .2s;min-height:130px;}'
    + '.bks-match:hover{box-shadow:0 4px 20px rgba(0,0,0,.13);}'
    + '.bks-match-ready{border-color:#a5d6a7;}'
    + '.bks-match-done{border-color:#2e7d32;}'
    + '.bks-match-live{border-color:#1565c0;box-shadow:0 0 0 3px rgba(21,101,192,.18);}'
    + '.bks-match-hdr{font-size:9px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;'
    +   'color:#bbb;padding:6px 12px 4px;background:#fafafa;border-bottom:1px solid #f0f0f0;border-radius:8px 8px 0 0;}'
    + '.bks-hdr-done{color:#2e7d32!important;background:#f1f8e9;}'
    + '.bks-live-pill{position:absolute;top:-10px;left:50%;transform:translateX(-50%);'
    +   'background:#1565c0;color:#fff;font-size:8px;font-weight:800;letter-spacing:.08em;'
    +   'text-transform:uppercase;padding:2px 9px;border-radius:8px;animation:bks-pulse 1.4s infinite;z-index:3;}'
    + '@keyframes bks-pulse{0%,100%{opacity:1;}50%{opacity:.4;}}'
    + '.bks-slot{display:flex;align-items:center;gap:9px;padding:9px 10px;min-height:52px;'
    +   'position:relative;transition:background .15s;cursor:pointer;}'
    + '.bks-slot:hover{filter:brightness(.97);}'
    + '.bks-winner-slot{background:#f0fff4!important;}'
    + '.bks-slot-divider{height:1px;background:linear-gradient(90deg,transparent,#e0e0e0 25%,#e0e0e0 75%,transparent);}'
    + '.bks-side-badge{font-size:8px;font-weight:800;text-transform:uppercase;letter-spacing:.07em;'
    +   'color:#fff;padding:2px 5px;border-radius:3px;flex-shrink:0;}'
    + '.bks-slot-info{flex:1;min-width:0;}'
    + '.bks-slot-name{font-size:12px;font-weight:700;color:#1a1a1a;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}'
    + '.bks-slot-club{font-size:10px;color:#9e9e9e;margin-top:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}'
    + '.bks-muted{color:#b0bec5!important;}'
    + '.bks-assign-label{font-size:11px;color:#b0bec5;flex:1;font-style:italic;padding-left:2px;}'
    + '.bks-score{font-size:17px;font-weight:800;color:#ccc;min-width:24px;text-align:center;flex-shrink:0;}'
    + '.bks-score-win{color:#2e7d32;}'
    + '.bks-slot-del{background:none;border:none;font-size:16px;color:#e0e0e0;cursor:pointer;'
    +   'padding:2px 5px;border-radius:4px;line-height:1;flex-shrink:0;}'
    + '.bks-slot-del:hover{color:#c62828;background:#ffebee;}'
    + '.bks-prov-tag{font-size:8px;color:#888;background:#eee;border-radius:3px;padding:1px 4px;margin-left:4px;font-weight:600;}'
    /* Right stub: extends from card right edge toward next round */
    + '.bks-stub-r{position:absolute;right:-20px;top:50%;width:20px;height:2px;background:#c8e6c9;'
    +   'transform:translateY(-50%);pointer-events:none;z-index:2;}'
    /* Left stub: extends from card left edge back toward previous round */
    + '.bks-stub-l{position:absolute;left:-20px;top:50%;width:20px;height:2px;background:#c8e6c9;'
    +   'transform:translateY(-50%);pointer-events:none;z-index:2;}'
    /* Vertical connector between a matched pair + horizontal midpoint stub */
    + '.bks-conn-v{position:relative;flex-shrink:0;pointer-events:none;}'
    + '.bks-conn-v::before{content:"";position:absolute;right:-21px;top:-65px;bottom:-65px;width:2px;background:#c8e6c9;}'
    + '.bks-conn-v::after{content:"";position:absolute;right:-40px;top:50%;width:19px;height:2px;background:#c8e6c9;transform:translateY(-50%);}'
    + '.bks-empty{text-align:center;color:#aaa;padding:60px 24px;font-size:13px;line-height:1.6;}';

    function injectCSS() {
        var id = 'skf-bks-engine-css';
        if (document.getElementById(id)) return;
        var el = document.createElement('style');
        el.id = id; el.textContent = CSS;
        (document.head || document.documentElement).appendChild(el);
    }

    W.SKFBracket = { renderSetup:renderSetup, renderView:renderView, injectCSS:injectCSS, css:CSS };

}(window));
