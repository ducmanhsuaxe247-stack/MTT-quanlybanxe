// Own authentication: possession of a 256-bit device secret AND owner approval.
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'content-type,apikey,authorization,x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('',{headers});
 const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
 if(req.method!=='POST')return reply({error:'METHOD'},405);
 try{
  const body=await req.text();if(body.length>2048)return reply({error:'INVALID'},400);
  const {id,secret}=JSON.parse(body);
  if(typeof id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(id)||typeof secret!=='string'||!/^[0-9a-f]{64}$/.test(secret))return reply({error:'INVALID'},400);
  const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(secret))),b=>b.toString(16).padStart(2,'0')).join('');
  const url=Deno.env.get('SUPABASE_URL')!, key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const serverHeaders={'apikey':key,'Authorization':'Bearer '+key,'Content-Type':'application/json'};
  async function rpc(name:string){const r=await fetch(url+'/rest/v1/rpc/'+name,{method:'POST',headers:serverHeaders,body:JSON.stringify({p_id:id,p_hash:hash})});if(!r.ok)throw Error('DENIED');return r.status===204?null:r.json();}
  let state=await rpc('mtt_device_authorize');
  if(state.status!=='approved')return reply({status:state.status});
  const email=id+'@device.mtt.invalid';
  if(!state.exists){
   // Synthetic device identity, not a verified Gmail address. No mail is sent.
   const r=await fetch(url+'/auth/v1/admin/users',{method:'POST',headers:serverHeaders,body:JSON.stringify({id,email,password:secret,email_confirm:true,app_metadata:{mtt_identity:'owner_approved_device'}})});
   if(!r.ok){state=await rpc('mtt_device_authorize');if(!state.exists)throw Error('CREATE');}
  }
  await rpc('mtt_activate_device');
  return reply({status:'approved',email});
 }catch{return reply({error:'Không thể xác nhận thiết bị. Hãy thử lại.'},403);}
});
