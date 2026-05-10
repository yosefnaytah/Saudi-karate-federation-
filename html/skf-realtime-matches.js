/**
 * Supabase Realtime helpers for tournament_matches.
 * Requires: supabase-js, valid JWT in localStorage.
 * Run database/phase17_realtime_tournament_matches.sql in Supabase once.
 */
(function (global) {
    'use strict';

    function subscribeTournamentMatches(sb, tournamentId, onPayload) {
        if (!sb || !tournamentId || typeof sb.channel !== 'function') {
            return { unsubscribe: function () {} };
        }
        var safeTid = String(tournamentId).replace(/[^-a-f0-9]/gi, '');
        if (!safeTid) return { unsubscribe: function () {} };

        var chName = 'skf-tm-' + safeTid.slice(0, 24);
        var ch = sb
            .channel(chName)
            .on(
                'postgres_changes',
                {
                    event: '*',
                    schema: 'public',
                    table: 'tournament_matches',
                    filter: 'tournament_id=eq.' + safeTid
                },
                function (payload) {
                    try {
                        if (typeof onPayload === 'function') onPayload(payload);
                    } catch (e) {
                        console.warn('[SKF realtime]', e);
                    }
                }
            )
            .subscribe(function (status, err) {
                if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
                    console.warn('[SKF realtime] channel', status, err || '');
                }
            });

        return {
            unsubscribe: function () {
                try {
                    sb.removeChannel(ch);
                } catch (e) { /* ignore */ }
            }
        };
    }

    /**
     * One channel, multiple postgres_changes filters (one per tournament).
     * Caps list length to avoid oversized channels.
     */
    function subscribeTournamentsMatches(sb, tournamentIds, onPayload) {
        if (!sb || !tournamentIds || !tournamentIds.length || typeof sb.channel !== 'function') {
            return { unsubscribe: function () {} };
        }
        var ids = [];
        tournamentIds.forEach(function (id) {
            var s = String(id || '').replace(/[^-a-f0-9]/gi, '');
            if (s && ids.indexOf(s) < 0) ids.push(s);
        });
        if (!ids.length) return { unsubscribe: function () {} };
        ids = ids.slice(0, 40);

        var chName = 'skf-tm-m-' + ids[0].slice(0, 12) + '-n' + ids.length;
        var ch = sb.channel(chName);
        var handler = function (payload) {
            try {
                if (typeof onPayload === 'function') onPayload(payload);
            } catch (e) {
                console.warn('[SKF realtime]', e);
            }
        };
        ids.forEach(function (safeTid) {
            ch = ch.on('postgres_changes', {
                event: '*',
                schema: 'public',
                table: 'tournament_matches',
                filter: 'tournament_id=eq.' + safeTid
            }, handler);
        });
        ch.subscribe(function (status, err) {
            if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
                console.warn('[SKF realtime] channel', status, err || '');
            }
        });
        return {
            unsubscribe: function () {
                try {
                    sb.removeChannel(ch);
                } catch (e) { /* ignore */ }
            }
        };
    }

    global.SKFMatchRealtime = {
        subscribeTournamentMatches: subscribeTournamentMatches,
        subscribeTournamentsMatches: subscribeTournamentsMatches
    };
})(typeof window !== 'undefined' ? window : this);
