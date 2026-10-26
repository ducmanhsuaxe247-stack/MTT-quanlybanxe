(function(root){
const escapeHTML=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function validateBackup(x){
 if(!x||typeof x!=='object')return false;
 const spec={bikes:{text:['brand','model'],num:['cost','price','repair','qty']},sales:{text:['bikeId','brand','model','seller','date'],num:['qty','price','cost']},expenses:{text:['type','date'],num:['amount']},targets:{text:['name','month'],num:['qty','money']}};
 return Object.entries(spec).every(([k,s])=>Array.isArray(x[k])&&x[k].length<=50000&&new Set(x[k].map(r=>r?.id)).size===x[k].length&&x[k].every(r=>r&&/^[A-Za-z0-9_-]{1,80}$/.test(r.id)&&s.text.every(f=>typeof r[f]==='string'&&r[f].length<=2000)&&s.num.every(f=>typeof r[f]==='number'&&Number.isFinite(r[f])&&r[f]>=0&&r[f]<=1e14)&&(!('qty' in r)||Number.isInteger(r.qty))&&(!('photo' in r)||!r.photo||/^data:image\/(jpeg|png|webp|gif);base64,[A-Za-z0-9+/=]+$/.test(r.photo))&&(!r.date||/^\d{4}-\d{2}-\d{2}$/.test(r.date))&&(!r.month||/^\d{4}-\d{2}$/.test(r.month))));
}
root.escapeHTML=escapeHTML;root.validateBackup=validateBackup;
if(typeof module!=='undefined')module.exports={escapeHTML,validateBackup};
})(globalThis);
