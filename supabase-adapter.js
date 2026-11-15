/* Adaptador pequeño de compatibilidad para conservar la lógica existente del juego.
   Guarda cada sala como un documento JSON en public.game_rooms y escucha cambios Realtime. */
(function () {
  const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
  const SERVER_TIMESTAMP = Object.freeze({ __serverTimestamp: true });
  const clone = v => v == null ? v : JSON.parse(JSON.stringify(v));
  const parts = p => String(p || '').split('/').filter(Boolean);
  function getAt(obj, path) { return path.reduce((v, k) => v == null ? undefined : v[k], obj); }
  function setAt(obj, path, value) {
    if (!path.length) return clone(value);
    let cur = obj;
    path.forEach((k, i) => { if (i === path.length - 1) { if (value === null) delete cur[k]; else cur[k] = clone(value); } else { if (!cur[k] || typeof cur[k] !== 'object') cur[k] = {}; cur = cur[k]; } });
    return obj;
  }
  function resolve(v) { if (v && v.__serverTimestamp) return Date.now(); if (Array.isArray(v)) return v.map(resolve); if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k,x])=>[k,resolve(x)])); return v; }
  class Snap { constructor(v){this.v=clone(v)} val(){return this.v===undefined?null:this.v} exists(){return this.v!==undefined&&this.v!==null} numChildren(){return this.v&&typeof this.v==='object'?Object.keys(this.v).length:0} }
  const roomWatchers = new Map();
  function watchRoom(code, handler) {
    let entry = roomWatchers.get(code);
    if (!entry) {
      entry = { handlers: new Set(), channel: null, running: false, pending: false, timer: null };
      const refresh = async () => {
        if (entry.running) { entry.pending = true; return; }
        entry.running = true;
        try {
          do {
            entry.pending = false;
            const { data, error } = await client.from('game_rooms').select('data').eq('code', code).maybeSingle();
            if (error) throw error;
            const value = data ? data.data : null;
            for (const fn of [...entry.handlers]) {
              try { fn(value); } catch (e) { console.error('Error actualizando sala:', e); }
            }
          } while (entry.pending);
        } catch (e) {
          console.error('No se pudo actualizar la sala:', e);
        } finally {
          entry.running = false;
        }
      };
      const schedule = () => {
        if (entry.timer) clearTimeout(entry.timer);
        entry.timer = setTimeout(() => { entry.timer = null; refresh(); }, 60);
      };
      entry.refresh = refresh;
      entry.channel = client.channel('room-' + code)
        .on('postgres_changes', {event:'*', schema:'public', table:'game_rooms', filter:`code=eq.${code}`}, schedule)
        .subscribe((status) => {
          if (status === 'SUBSCRIBED') schedule();
          if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
            console.warn('Realtime de Supabase:', status);
            schedule();
          }
        });
      roomWatchers.set(code, entry);
    }
    entry.handlers.add(handler);
    entry.refresh();
    return () => {
      entry.handlers.delete(handler);
      if (!entry.handlers.size) {
        if (entry.timer) clearTimeout(entry.timer);
        client.removeChannel(entry.channel);
        roomWatchers.delete(code);
      }
    };
  }
  class Ref {
    constructor(path){this.path=parts(path);this.handlers=[];this.unwatch=null;this.parentCode=this.path[0]==='rooms'?this.path[1]:null;}
    child(p){return new Ref([...this.path,p].join('/'))}
    async _row(){if(!this.parentCode)return null;const {data,error}=await client.from('game_rooms').select('data').eq('code',this.parentCode).maybeSingle();if(error)throw error;return data?data.data:null}
    async _write(next){const code=this.parentCode;if(!code)throw new Error('Ruta no válida');const current=await this._row();const payload={code,data:resolve(next),updated_at:new Date().toISOString()};let q=current===null?client.from('game_rooms').insert(payload):client.from('game_rooms').update({data:payload.data,updated_at:payload.updated_at}).eq('code',code);const {error}=await q;if(error)throw error;return next;}
    async once(){if(this.path[0]==='.info')return new Snap(this.path[1]==='connected'?true:0);const row=await this._row();return new Snap(getAt(row,this.path.slice(2)));}
    on(event,fn){
      if(event!=='value')return this;
      const deliver = value => { try { fn(new Snap(getAt(value, this.path.slice(2)))); } catch(e) { console.error(e); } };
      this.handlers.push(fn);
      if(this.parentCode&&!this.unwatch)this.unwatch=watchRoom(this.parentCode,deliver);
      else if(!this.parentCode)this.once().then(fn).catch(console.error);
      return this;
    }
    off(){this.handlers=[];if(this.unwatch){this.unwatch();this.unwatch=null;}return this;}
    async _patch(path,value,remove=false){
      const {data,error}=await client.rpc('patch_game_room',{p_code:this.parentCode,p_path:path.map(String),p_value:remove?null:resolve(value),p_delete:remove});
      if(error)throw error;return data;
    }
    async set(value){await this._patch(this.path.slice(2),value,value===null);return {committed:true};}
    async update(values){
      for(const [k,v] of Object.entries(values)){
        const path=[...this.path.slice(2),...parts(k)];
        await this._patch(path,v,v===null);
      }
      return {committed:true};
    }
    async remove(){return this.set(null)}
    async submitAnswer(game,round,uid,answer,points){
      const {data,error}=await client.rpc('submit_game_answer',{p_code:this.parentCode,p_game:String(game),p_round:String(round),p_uid:String(uid),p_answer:resolve(answer),p_points:Number(points)});
      if(error)throw error;return {committed:!!data};
    }
    async transaction(fn){const row=await this._row()||{};const path=this.path.slice(2);const old=getAt(row,path);const value=fn(clone(old));if(value===undefined)return {committed:false,snapshot:new Snap(old)};await this._patch(path,value,value===null);return {committed:true,snapshot:new Snap(value)};}
    onDisconnect(){return {set:async()=>{},cancel:async()=>{}}}
  }
  const db={ref:path=>new Ref(path)};
  window.firebase={database:()=>db,auth:()=>({onAuthStateChanged:cb=>client.auth.getSession().then(({data})=>cb(data.session?.user||null)).then(()=>client.auth.onAuthStateChange((_e,s)=>cb(s?.user||null))),signInAnonymously:()=>client.auth.signInAnonymously()}),initializeApp:()=>{},databaseServerTimestamp:SERVER_TIMESTAMP};
  window.firebase.database.ServerValue={TIMESTAMP:SERVER_TIMESTAMP};
  window.__supabaseClient=client;
})();
