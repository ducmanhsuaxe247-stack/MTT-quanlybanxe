import {mkdir,copyFile,rm} from 'node:fs/promises';
await rm('dist',{recursive:true,force:true});await mkdir('dist/vendor',{recursive:true});
for(const f of ['index.html','app.js','cloud.js','validation.js','config.js','manifest.webmanifest','icon.svg','MTT_Mo_Truc_Tiep-2.html'])await copyFile(f,'dist/'+f);
await copyFile('vendor/supabase.js','dist/vendor/supabase.js');
console.log('Built static MTT application.');
