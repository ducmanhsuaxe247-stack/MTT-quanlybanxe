/* Only the server can approve access; a typed email is never proof of identity. */
let accessLoading=false,accessRequests=[];
const accessRoleName=r=>r==='editor'?'Quản trị':'Nhân viên bán hàng';
function requestCards(rows){
 return rows.length?rows.map(r=>`<article style="padding:16px 0;border-bottom:1px solid var(--line)"><b>${escapeHTML(r.full_name)}</b><br>${escapeHTML(r.email)}${r.kind==='device'?'<br><small>Thiết bị '+escapeHTML(r.id.slice(0,8))+' · Gmail tự khai, chưa xác minh</small>':'<br><small>Yêu cầu email cũ</small>'}<p>${r.status==='pending'?'Chờ duyệt':r.status==='approved'?'Đã duyệt · '+accessRoleName(r.granted_role):'Đã từ chối / thu hồi quyền'} · ${escapeHTML(new Date(r.requested_at).toLocaleString('vi-VN'))}</p><div class="actions"><button data-request="${escapeHTML(r.id)}" data-access-role="sales">Duyệt nhân viên</button><button data-request="${escapeHTML(r.id)}" data-access-role="editor" class="secondary">Duyệt quản trị</button><button data-request="${escapeHTML(r.id)}" data-access-role="rejected" class="danger">${r.status==='approved'?'Thu hồi quyền':'Từ chối'}</button></div></article>`).join(''):'<p>Không có yêu cầu chờ duyệt.</p>';
}
window.refreshAccess=async()=>{
 const owner=profile?.role==='owner';$('requestInbox').classList.toggle('hidden',!owner);$('usersNav').classList.toggle('hidden',!owner);
 if(!owner||accessLoading)return;accessLoading=true;
 try{accessRequests=await rpc('mtt_list_requests');if(profile?.role!=='owner')return;
 const pending=accessRequests.filter(r=>r.status==='pending');$('requestCount').textContent=pending.length+' yêu cầu đang chờ anh duyệt';$('dashboardRequests').innerHTML=requestCards(pending);$('allRequests').innerHTML=requestCards(accessRequests);$('requestAdminStatus').textContent='';
 }catch(e){$('requestAdminStatus').textContent=errorText(e);$('requestCount').textContent='Chưa tải được yêu cầu. Bấm Đồng bộ để thử lại.';}finally{accessLoading=false;}
};
const accessBaseRender=render;render=()=>{accessBaseRender();$('usersNav').classList.toggle('hidden',profile?.role!=='owner');if(profile?.role!=='owner'&&page==='users')setPage('dashboard');};
window.clearAccess=()=>{stopWaiting();accessRequests=[];$('dashboardRequests').replaceChildren();$('allRequests').replaceChildren();$('requestInbox').classList.add('hidden');};
$('refreshRequests').onclick=()=>window.refreshAccess();
for(const id of ['dashboardRequests','allRequests'])$(id).addEventListener('click',async e=>{
 const b=e.target.closest('button[data-request]');if(!b||profile?.role!=='owner')return;
 const r=accessRequests.find(r=>r.id===b.dataset.request);if(!r)return;
 document.querySelectorAll('[data-request]').forEach(b=>b.disabled=true);
 try{await rpc(r.kind==='device'?'mtt_review_device':'mtt_review_request',{p_id:r.id,p_role:b.dataset.accessRole});await window.refreshAccess();message('Đã cập nhật quyền cho '+r.full_name+'.');}
 catch(err){message(errorText(err));$('requestAdminStatus').textContent=errorText(err);}
 finally{document.querySelectorAll('[data-request]').forEach(b=>b.disabled=false);}
});
let approvalTimer=null,waitGeneration=0;
const deviceStorageKey='mtt_approved_device_v1';
function readDevice(){try{const d=JSON.parse(localStorage.getItem(deviceStorageKey)||'null');return d&&/^[0-9a-f-]{36}$/.test(d.id)&&/^[0-9a-f]{64}$/.test(d.secret)?d:null;}catch{return null;}}
function stopWaiting(){clearTimeout(approvalTimer);approvalTimer=null;waitGeneration++;$('requestForm').classList.remove('hidden');$('cancelWaiting').classList.add('hidden');}
async function waitForDevice(d,generation){
 if(generation!==waitGeneration)return;
 try{
  const {data,error}=await client.functions.invoke('mtt-device-session',{body:{id:d.id,secret:d.secret}});
  if(generation!==waitGeneration)return;
  if(error)throw error;
  if(data.status==='approved'){
   const result=await client.auth.signInWithPassword({email:data.email,password:d.secret});
   if(generation!==waitGeneration)return;
   if(result.error)throw result.error;
   stopWaiting();await enterApp();return;
  }
  if(data.status==='rejected'){$('requestStatus').textContent='Thiết bị đã bị từ chối hoặc thu hồi quyền. Liên hệ chủ cửa hàng. Mã thiết bị: '+d.id.slice(0,8);return;}
  $('requestStatus').textContent='Đang chờ chủ cửa hàng duyệt. Mã thiết bị: '+d.id.slice(0,8)+'. Giữ trang này mở; được duyệt app sẽ tự vào.';
  approvalTimer=setTimeout(()=>waitForDevice(d,generation),5000);
 }catch(err){if(generation!==waitGeneration)return;$('requestStatus').textContent='Chưa kết nối được máy chủ. Đang thử lại…';approvalTimer=setTimeout(()=>waitForDevice(d,generation),10000);}
}
function startDeviceWait(d){stopWaiting();$('requestForm').classList.add('hidden');$('cancelWaiting').classList.remove('hidden');$('requestStatus').textContent='Đang kiểm tra quyền thiết bị…';waitForDevice(d,waitGeneration);}
$('cancelWaiting').onclick=async()=>{stopWaiting();await signOut();$('requestStatus').textContent='';};
$('loginForm').addEventListener('submit',()=>stopWaiting());
$('requestForm').onsubmit=async e=>{
 e.preventDefault();$('requestSubmit').disabled=true;
 try{
  const email=$('requestEmail').value.trim().toLowerCase(),name=$('requestName').value.trim();
  let d=readDevice();
  if(!d||d.email!==email){d={id:crypto.randomUUID(),secret:Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join(''),email,name};}
  // Save before submitting, so loss of storage cannot orphan a newly approved device.
  localStorage.setItem(deviceStorageKey,JSON.stringify(d));
  const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(d.secret))),b=>b.toString(16).padStart(2,'0')).join('');
  await rpc('mtt_request_device',{p_id:d.id,p_hash:hash,p_email:d.email,p_name:d.name});
  startDeviceWait(d);
 }catch(err){$('requestStatus').textContent=errorText(err);}finally{$('requestSubmit').disabled=false;}
};
// Saved device possession is the credential, never the typed Gmail address.
const savedDevice=readDevice();if(savedDevice){$('requestName').value=savedDevice.name;$('requestEmail').value=savedDevice.email;startDeviceWait(savedDevice);}
