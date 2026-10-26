/* Only the server can approve access; a typed email is never proof of identity. */
let accessLoading=false,accessRequests=[];
const accessRoleName=r=>r==='editor'?'Quản trị':'Nhân viên bán hàng';
function requestCards(rows){
 return rows.length?rows.map(r=>`<article style="padding:16px 0;border-bottom:1px solid var(--line)"><b>${escapeHTML(r.full_name)}</b><br>${escapeHTML(r.email)}<p>${r.status==='pending'?'Chờ duyệt':r.status==='approved'?'Đã duyệt · '+accessRoleName(r.granted_role):'Đã từ chối / thu hồi quyền'} · ${escapeHTML(new Date(r.requested_at).toLocaleString('vi-VN'))}</p><div class="actions"><button data-request="${escapeHTML(r.id)}" data-access-role="sales">Duyệt nhân viên</button><button data-request="${escapeHTML(r.id)}" data-access-role="editor" class="secondary">Duyệt quản trị</button><button data-request="${escapeHTML(r.id)}" data-access-role="rejected" class="danger">${r.status==='approved'?'Thu hồi quyền':'Từ chối'}</button></div></article>`).join(''):'<p>Không có yêu cầu chờ duyệt.</p>';
}
window.refreshAccess=async()=>{
 const owner=profile?.role==='owner';$('requestInbox').classList.toggle('hidden',!owner);$('usersNav').classList.toggle('hidden',!owner);
 if(!owner||accessLoading)return;accessLoading=true;
 try{accessRequests=await rpc('mtt_list_requests');if(profile?.role!=='owner')return;
 const pending=accessRequests.filter(r=>r.status==='pending');$('requestCount').textContent=pending.length+' yêu cầu đang chờ anh duyệt';$('dashboardRequests').innerHTML=requestCards(pending);$('allRequests').innerHTML=requestCards(accessRequests);$('requestAdminStatus').textContent='';
 }catch(e){$('requestAdminStatus').textContent=errorText(e);$('requestCount').textContent='Chưa tải được yêu cầu. Bấm Đồng bộ để thử lại.';}finally{accessLoading=false;}
};
const accessBaseRender=render;render=()=>{accessBaseRender();$('usersNav').classList.toggle('hidden',profile?.role!=='owner');if(profile?.role!=='owner'&&page==='users')setPage('dashboard');};
window.clearAccess=()=>{accessRequests=[];$('dashboardRequests').replaceChildren();$('allRequests').replaceChildren();$('requestInbox').classList.add('hidden');};
$('refreshRequests').onclick=()=>window.refreshAccess();
for(const id of ['dashboardRequests','allRequests'])$(id).addEventListener('click',async e=>{
 const b=e.target.closest('button[data-request]');if(!b||profile?.role!=='owner')return;
 const r=accessRequests.find(r=>r.id===b.dataset.request);if(!r)return;
 document.querySelectorAll('[data-request]').forEach(b=>b.disabled=true);
 try{await rpc('mtt_review_request',{p_id:r.id,p_role:b.dataset.accessRole});await window.refreshAccess();message('Đã cập nhật quyền cho '+r.full_name+'.');}
 catch(err){message(errorText(err));$('requestAdminStatus').textContent=errorText(err);}
 finally{document.querySelectorAll('[data-request]').forEach(b=>b.disabled=false);}
});
$('requestForm').onsubmit=async e=>{
 e.preventDefault();$('requestSubmit').disabled=true;const email=$('requestEmail').value.trim().toLowerCase();
 try{await rpc('mtt_request_access',{p_email:email,p_name:$('requestName').value.trim()});$('staffEmail').value=email;$('requestStatus').textContent='Đã tiếp nhận yêu cầu. Chủ cửa hàng sẽ duyệt quyền Nhân viên bán hàng hoặc Quản trị. Khi được duyệt, nhận liên kết đăng nhập bên dưới.';}
 catch(err){$('requestStatus').textContent=errorText(err);}finally{$('requestSubmit').disabled=false;}
};
$('staffLoginForm').onsubmit=async e=>{
 e.preventDefault();$('staffLoginSubmit').disabled=true;
 try{if(!client)throw Error('Chưa kết nối máy chủ.');const {error}=await client.auth.signInWithOtp({email:$('staffEmail').value.trim().toLowerCase(),options:{emailRedirectTo:new URL('./',location.href).href}});if(error)throw error;$('staffLoginStatus').textContent='Hãy mở Gmail và bấm liên kết đăng nhập. Nếu chưa thấy, kiểm tra thư rác.';}
 catch(err){$('staffLoginStatus').textContent='Chưa gửi được email đăng nhập. '+(err.message||'Hãy thử lại sau.');}finally{$('staffLoginSubmit').disabled=false;}
};
// Supabase implicit email callback, accepted only after server-side verification.
(async()=>{
 const hash=new URLSearchParams(location.hash.slice(1));
 if(!hash.has('access_token')&&!hash.has('error_description'))return;
 history.replaceState(null,'',location.pathname+location.search);
 try{if(hash.has('error_description'))throw Error(hash.get('error_description'));if(!client)throw Error('Chưa kết nối máy chủ.');
 const {error}=await client.auth.setSession({access_token:hash.get('access_token'),refresh_token:hash.get('refresh_token')||''});if(error)throw error;
 await enterApp();
 }catch(err){await signOut();$('loginStatus').textContent=errorText(err);}
})();
