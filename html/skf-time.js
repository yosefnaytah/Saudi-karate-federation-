/**
 * SKF app convention: store timestamps in UTC; display in Asia/Riyadh.
 */
var SKF_TIMEZONE = 'Asia/Riyadh';

function formatSkfDateTime(isoString) {
    if (!isoString) return '—';
    try {
        var d = new Date(isoString);
        if (isNaN(d.getTime())) return String(isoString);
        return new Intl.DateTimeFormat('en-SA', {
            timeZone: SKF_TIMEZONE,
            dateStyle: 'medium',
            timeStyle: 'short'
        }).format(d);
    } catch (e) {
        return String(isoString);
    }
}

window.SKF_TIMEZONE = SKF_TIMEZONE;
window.formatSkfDateTime = formatSkfDateTime;
