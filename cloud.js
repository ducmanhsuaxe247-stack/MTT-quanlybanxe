/* Supabase is authoritative. No business data or auth tokens persist in browser storage. */
let client=null,revision=0,confirmed=null,busy=false,profile=null,poll=null;
const $=id=>document.getElementById(id);
const emptyDB=()=>({bikes:[],sales:[],expenses:[],targets:[]});
function message(t){$('syncStatus').textContent=t;}
function lock(on){busy=on;document.querySelectorAll('#appShell button,#appShell input,#appShell select').forEach(e=>e.disabled=on);}
function accountView(){
 const owner=role==='owner';$('seller').readOnly=!owner;
 document.querySelectorAll('.nav').forEach(e=>e.classList.toggle('hidden',!owner&&!['inventory','sales'].includes(e.dataset.page)));
 $('mttImport').classList.toggle('hidden',!owner);$('mttExport').classList.toggle('hidden',!owner);
 $('accountLabel').textContent=(profile?.full_name||'Tài khoản')+' · '+(owner?'Quản trị':'Nhân viên');
 if(!owner){$('inventoryMetrics').innerHTML=card('XE ĐANG TỒN',num(stockCount())+' xe','Số lượng hiện có');$('seller').value=profile?.full_name||'';$('seller').readOnly=true;}
 const months=[...new Set([monthNow(),...db.expenses.map(e=>e.date.slice(0,7))])].sort().reverse();
 const selected=$('expenseMonth').value;$('expenseMonth').innerHTML=months.map(m=>`<option value="${escapeHTML(m)}">${escapeHTML(m)}</option>`).join('');if(months.includes(selected))$('expenseMonth').value=selected;
}
const baseRender=render;render=()=>{baseRender();accountView();};
const baseInventory=renderInventory;renderInventory=()=>{const selected=$('saleBike').value;baseInventory();if([...$('saleBike').options].some(o=>o.value===selected))$('saleBike').value=selected;if(role!=='owner')$('inventoryMetrics').innerHTML=card('XE ĐANG TỒN',num(stockCount())+' xe','Số lượng hiện có');};
function acceptState(data){
 if(!data||!data.data||!Number.isInteger(data.revision))throw Error('Máy chủ trả dữ liệu không hợp lệ.');
 db=data.data;revision=data.revision;confirmed=structuredClone(db);profile=data.profile;role=profile.role==='owner'?'owner':'staff';
 render();message('Đã đồng bộ lúc '+new Date().toLocaleTimeString('vi-VN')+' · Phiên bản '+revision);
}
async function rpc(name,args={}){if(!client)throw Error('Chưa cấu hình Supabase.');const {data,error}=await client.rpc(name,args);if(error)throw error;return data;}
function errorText(e){if(e.message?.includes('MTT_CONFLICT'))return 'Dữ liệu đã đổi trên thiết bị khác. Đã tải bản mới; hãy kiểm tra và thực hiện lại.';if(e.message?.includes('MTT_DENIED'))return 'Tài khoản chưa được cấp quyền hoặc đã bị khóa.';if(e.message?.includes('MTT_STOCK'))return 'Số lượng xe không đủ. Hãy đồng bộ và kiểm tra lại.';return 'Không hoàn tất: '+(e.message||'Mất kết nối. Hãy thử lại.');}
async function refresh(manual=false){if(busy||!client||!profile)return;lock(true);try{const data=await rpc('mtt_load');if(data.revision!==revision||manual)acceptState(data);else message('Kết nối tốt · Phiên bản '+revision);}catch(e){message(errorText(e));if(e.message?.includes('MTT_DENIED'))await signOut();}finally{lock(false);}}
async function perform(name,args){
 if(busy)return false;
 lock(true);message('Đang gửi dữ liệu tới máy chủ…');
 try{acceptState(await rpc(name,args));return true;}
 catch(e){if(confirmed)db=structuredClone(confirmed);render();
  if(e.message?.includes('MTT_CONFLICT')){try{acceptState(await rpc('mtt_load'));}catch{}}
  message(errorText(e));alert(errorText(e));return false;
 }finally{lock(false);}
}
async function save(){
 if(role!=='owner'||busy){if(confirmed)db=structuredClone(confirmed);return false;}
 if(!validateBackup(db)){db=structuredClone(confirmed);render();alert('Dữ liệu chưa hợp lệ. Kiểm tra số tiền, số lượng và ngày.');return false;}
 return perform('mtt_save',{p_data:structuredClone(db),p_revision:revision});
}
function exportBackup(){if(role!=='owner')return;const blob=new Blob([JSON.stringify({application:'MTT',backupVersion:1,exportedAt:new Date().toISOString(),data:db},null,2)],{type:'application/json'});const u=URL.createObjectURL(blob),a=document.createElement('a');a.href=u;a.download='MTT_sao_luu_'+today()+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(u),2000);}
async function importBackup(f){if(!f||role!=='owner')return;try{if(f.size>15*1024*1024)throw Error('Tệp quá 15 MB.');const x=JSON.parse(await f.text());if(x.application!=='MTT'||x.backupVersion!==1||!validateBackup(x.data))throw Error('Tệp sao lưu không hợp lệ.');if(!confirm('Nhập sao lưu sẽ thay thế dữ liệu chung trên máy chủ. Hãy xuất sao lưu hiện tại trước. Tiếp tục?'))return;db=x.data;await save();}catch(e){alert(e.message);}}
async function signOut(){clearInterval(poll);profile=null;role='guest';db=emptyDB();confirmed=null;revision=0;document.querySelectorAll('#appShell form').forEach(f=>f.reset());photoData='';pendingSale=null;render();$('appShell').classList.add('hidden');$('loginScreen').classList.remove('hidden');$('loginPassword').value='';if(client)await client.auth.signOut({scope:'local'});}
function readConfig(){try{return window.MTT_CONFIG?.url?window.MTT_CONFIG:JSON.parse(localStorage.getItem('mtt_public_connection')||'null');}catch{return null;}}
function validateConfig(c){if(!c||!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(c.url))throw Error('Project URL phải là địa chỉ HTTPS của Supabase.');if(c.key.startsWith('sb_publishable_'))return;try{const payload=JSON.parse(atob(c.key.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));if(payload.role==='anon')return;}catch{}throw Error('Chỉ dùng Publishable key hoặc anon key. Không dùng khóa bí mật.');}
function connect(c){validateConfig(c);if(!window.supabase?.createClient)throw Error('Không tải được thư viện kết nối. Hãy tải lại trang.');client=window.supabase.createClient(c.url,c.key,{auth:{persistSession:false,autoRefreshToken:true,detectSessionInUrl:false}});$('projectUrl').value=c.url;$('publicKey').value=c.key;$('loginStatus').textContent='Kết nối đã cấu hình. Nhập tài khoản được cấp quyền để đăng nhập.';$('connectionDetails').open=false;}
$('connectionForm').onsubmit=e=>{e.preventDefault();try{const c={url:$('projectUrl').value.trim().replace(/\/$/,''),key:$('publicKey').value.trim()};connect(c);localStorage.setItem('mtt_public_connection',JSON.stringify(c));}catch(e){$('loginStatus').textContent=e.message;}};
$('loginForm').onsubmit=async e=>{e.preventDefault();if(!client){$('loginStatus').textContent='Cần cấu hình kết nối Supabase trước.';$('connectionDetails').open=true;return;}$('loginSubmit').disabled=true;try{
 const email=$('loginIdentity').value.trim();
 const {error}=await client.auth.signInWithPassword({email,password:$('loginPassword').value});if(error)throw Error('Đăng nhập không thành công. Kiểm tra tài khoản, mật khẩu và kết nối.');
 const state=await rpc('mtt_load');acceptState(state);$('loginPassword').value='';$('loginScreen').classList.add('hidden');$('appShell').classList.remove('hidden');setPage(role==='owner'?'dashboard':'inventory');clearInterval(poll);poll=setInterval(()=>{if(document.visibilityState==='visible'&&!document.querySelector('.panel:not(.hidden) form input:focus')&&!document.querySelector('#bikeFormPanel:not(.hidden),#targetFormPanel:not(.hidden),#expenseFormPanel:not(.hidden)'))refresh();},30000);
 }catch(e){$('loginStatus').textContent=errorText(e);await signOut();}finally{$('loginSubmit').disabled=false;}};
$('logoutBtn').onclick=()=>signOut();$('syncBtn').onclick=()=>refresh(true);$('mttExport').onclick=exportBackup;$('mttImport').onclick=()=>$('mttBackupFile').click();$('mttBackupFile').onchange=e=>{importBackup(e.target.files[0]);e.target.value='';};
window.addEventListener('offline',()=>message('Mất mạng. Chưa thể lưu lên máy chủ; không ghi nhận bán xe khi chưa được xác nhận.'));
try{const c=readConfig();if(c)connect(c);else{$('loginStatus').textContent='Chưa kết nối Supabase. Cần cấu hình dự án và cấp tài khoản trước khi sử dụng.';$('connectionDetails').open=true;}}catch(e){$('loginStatus').textContent=e.message;$('connectionDetails').open=true;}

$('inventorySearch').oninput=()=>renderInventory();$('stockFilter').onchange=()=>renderInventory();
