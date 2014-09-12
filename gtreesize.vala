/*
 * Package: treesize
 * Author:  Frank Duckhorn
 *
 * Copyright (c) 2013 Frank Duckhorn
 *
 * treesize is free software: you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 2 of the License, or (at your option)
 * any later version.
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

namespace Treesize {
	static string[] args;
	public static int main(string[] _args){
		Gtk.init(ref _args);
		args=_args;
		GLib.Environment.set_application_name("gTreesize");
		var tmp=new Treesize(); tmp.destroy();
		new Gtk.Builder.from_resource("/org/gtreesize/gtreesize.xml");
		Gtk.main();
		return 0;
	}
	public class Treesize : Gtk.Window, Gtk.Buildable {
		[ Signal ( action = true ) ] public signal void acc_open();
		[ Signal ( action = true ) ] public signal void acc_del();
		[ Signal ( action = true ) ] public signal void acc_upd();
		[ Signal ( action = true ) ] public signal void acc_add();
		[ Signal ( action = true ) ] public signal void acc_diff();
		[ Signal ( action = true ) ] public signal void acc_quit();

		private GLib.List<Gtk.MenuItem> mu_one_sel;
		private const Gtk.TargetEntry[] _dragtarget = { {"text/plain",0,0} };
		private Gdk.Cursor cur_def;
		private Gdk.Cursor cur_wait;

		private FileTree tm;
		private Gtk.TreeView tv;
		private Gtk.Menu mu;

		public Treesize(){}
		public void parser_finished(Gtk.Builder builder){
			// FileTree
			tm=builder.get_object("filetree") as FileTree;
			// TreeView
			tv=builder.get_object("treesize-tv") as Gtk.TreeView;
			tv.enable_model_drag_source(Gdk.ModifierType.BUTTON1_MASK,_dragtarget,Gdk.DragAction.COPY);
			tv.enable_model_drag_dest(_dragtarget,Gdk.DragAction.COPY);
			// Menu
			mu=builder.get_object("menu") as Gtk.Menu;
			mu_one_sel.prepend(builder.get_object("menu-open")   as Gtk.MenuItem); // TODO -> xml
			mu_one_sel.prepend(builder.get_object("menu-delete") as Gtk.MenuItem); // TODO -> xml
			on_sel_chg(tv.get_selection());
			// Cursor
			cur_def=get_window().get_cursor(); // TODO -> xml
			cur_wait=new Gdk.Cursor(Gdk.CursorType.WATCH); // TODO -> xml
			// Finish
			builder.connect_signals(this);
			show();
		}
		protected void on_refresh(){ tm.refresh(null); }
		protected void on_open(){    tm.runcmd("xdg-open",tv.get_selection()); }
		protected void on_del(){     tm.runcmd("rm -rf",  tv.get_selection()); }
		protected bool on_menu(Gdk.EventButton ev){
			if(ev.button!=3) return false;
			mu.popup(null,null,null,ev.button,Gtk.get_current_event_time());
			return true;
		}
		protected void on_setcur(bool wait){
			get_window().set_cursor(wait?cur_wait:cur_def);
		}
		protected void on_sel_chg(Gtk.TreeSelection s){
			int n=s.count_selected_rows();
			foreach(var i in mu_one_sel) i.sensitive=(n==1);
		}
		protected void on_drag_get(Gdk.DragContext ctx,Gtk.SelectionData sdat,uint info,uint time){
			Gtk.TreeIter iter; tv.get_selection().get_selected(null,out iter);
			string fn=tm.get_fn(iter);
			sdat.set_text(fn,fn.length);
		}
		protected void on_drag_rec(Gdk.DragContext ctx,int x,int y,Gtk.SelectionData sdat,uint info,uint time){
			string? fn=sdat.get_text();
			if(fn!=null) tm.adddir(fn);
		}
	}

	public delegate void CheckFunc();
	public class Queue {
		private GLib.HashTable<FileNode,int> hst=new GLib.HashTable<FileNode,int>(null,null);
		private CheckFunc check;
		public Queue(CheckFunc _check){ check=_check; }
		public bool insert(FileNode fn,int _depth=-1){
			int depth;
			if(hst.lookup_extended(fn,null,out depth)){
				if(depth>=0 && (_depth<0 ||_depth>depth))
					hst.set(fn,_depth);
				return false;
			}
			hst.insert(fn,_depth);
			check();
			return true;
		}
		public bool empty(){ return hst.size()==0; }
		public uint size(){ return hst.size(); }
		public bool pop(out FileNode? fn,out int depth){
			fn=null; depth=0;
			if(empty()) return false;
			FileNode? xfn=null; int xd=-1;
			hst.find((k,v)=>{ xfn=k; xd=v; return true; });
			fn=xfn; depth=xd;
			hst.remove(fn);
			return true;
		}
	}

	public class FileTree : Gtk.TreeStore, Gtk.TreeModel, Gtk.Buildable {
		public enum Col { FN,DFN,SSI,RSSI,RSPI,ACT,BN,MTIME,MODE,USER,GROUP,SIZE,NUM }
		public signal void setcur(bool wait);
		public Queue upddpl;
		private Queue updfile;
		public GLib.HashTable<string,FileNode> fns=new GLib.HashTable<string,FileNode>(str_hash,str_equal);
		private bool updateon=false;
		private time_t lastupd=0;
		private Gtk.FileChooserDialog fc;
		private bool diff=false;
		public bool fsys_only=true;
		public bool isdiff(){ return diff; }
		public void parser_finished(Gtk.Builder builder){
			fc=builder.get_object("fc") as Gtk.FileChooserDialog;
			upddpl=new Queue(updcheck);
			updfile=new Queue(updcheck);
			set_sort_column_id(Col.SSI,Gtk.SortType.DESCENDING);
			int i;
			bool _diff=false;
			for(i=1;true;i++){
				if(args[i]=="-d") _diff=true;
				else if(args[i]=="-m") fsys_only=false;
				#if DEBUG
				else if(args[i]=="-v") Debug.inc_level();
				#endif
				else if(args[i]=="-h"){
					stdout.printf("Usage: gtreesize [-d] [-m] [-h] {DIRS|FINDFILES}\n");
					stdout.printf("         -d (+ 2 DIRS) => diff mode\n");
					stdout.printf("         -m run over multiple filesystems\n");
					#if DEBUG
					stdout.printf("         -v verbose mode\n");
					#endif
					stdout.printf("         -h show help\n");
					stdout.printf("         FINDFILES output of: find -printf \"%%k %%p\\n\"\n");
					Posix.exit(1);
				}else break;
			}
			if(_diff){
				if(args.length!=i+2){
					stdout.printf("Error: exactly two arguments required for diff mode\n");
					Posix.exit(1);
				}
				adddir(args[i]);
				adddir(args[i+1],true);
			}else if(i<args.length) for(;i<args.length;i++) adddir(args[i]);
			else seldir();
		}
		protected void diffdir(){ seldir(true); }
		protected void seldir(bool _diff=false){
			if(fc.run()==Gtk.ResponseType.ACCEPT) adddir(fc.get_filename(),_diff);
			fc.hide();
		}
		public void adddir(string dirname,bool _diff=false){
			var fi=File.new_for_path(dirname);
			if(fi.query_file_type(FileQueryInfoFlags.NONE)==FileType.REGULAR) read_find(dirname,_diff);
			else updfile_insert(new FileNode(dirname,this,null,_diff));
			if(_diff) diff=true;
		}
		private bool it2fn(Gtk.TreeIter it,out FileNode? fn){
			GLib.Value vfn; base.get_value(it,Col.DFN,out vfn);
			string sfn=vfn.get_string();
			return (fn= sfn=="" ? null : fns.lookup(sfn))!=null;
		}
		public void get_value(Gtk.TreeIter iter,int column,out GLib.Value val){
			if(column!=Col.RSSI && column!=Col.RSPI){
				base.get_value(iter,column,out val);
			}else{
				FileNode fn;
				if(it2fn(iter,out fn) && !fn.get_vis()){ upddpl.insert(fn); fn.set_vis(); }
				fn=fn.get_prim();
				switch(column){
				case Col.RSSI:
					val=Value(typeof(string));
					if(fn!=null) val.set_string(fn.rnd_ssi());
				break;
				case Col.RSPI:
					val=Value(typeof(int));
					if(fn!=null) val.set_int(fn.rnd_spi());
				break;
				}
			}
		}
		public string get_str(Gtk.TreeIter iter,Col col){ string s; get(iter,col,out s); return s; }
		public string get_fn(Gtk.TreeIter iter){ return get_str(iter,Col.FN); }
		public bool update(){
			Timer.timer(0,-1);
			time_t t=time_t();
			bool tchg=t!=lastupd;
			lastupd=t;
			FileNode fn;
			int depth;
			if(!upddpl.empty() && (updfile.empty() || tchg))
				while(upddpl.pop(out fn,out depth)){
					if(!fn.del){
						fn=fn.get_prim();
						FileNode? fn2=fn.get_oth();
						if(fn.get_ssichg() || (fn2!=null && fn2.get_ssichg())){
							int64 ssi=fn.get_ssi();
							if(fn2!=null) ssi=(ssi-fn2.get_ssi()).abs();
							set(fn.get_it(),Col.SSI,ssi);
						}else row_changed(get_path(fn.get_it()),fn.get_it());
					}
				}
			else if(!updfile.empty()) if(updfile.pop(out fn,out depth)) fn.updfile(depth);
			bool nupdateon=!(updfile.empty() && upddpl.empty());
			Timer.timer(0,0);
			if(nupdateon!=updateon) setcur(nupdateon);
			if(updateon && !nupdateon){ Timer.timer(1,-2); Timer.timer(0,-2); }
			return updateon=nupdateon;
		}
		public void updcheck(){ if(!updateon) GLib.Idle.add(update); }
		public void updfile_insert(FileNode fn,int depth=-1){
			if(!fn.is_fix() && updfile.insert(fn,depth)) fn.on_upd();
		}
		public void refresh(Gtk.TreeSelection? s){
			if(s!=null) s.selected_foreach((tm,tp,it)=>{
					FileNode fn;
					if(it2fn(it,out fn)){
						updfile_insert(fn);
						if((fn=fn.get_oth())!=null) updfile_insert(fn);
					}
					});
			else base.foreach((tm,tp,it)=>{
					FileNode fn;
					if(it2fn(it,out fn)){
						updfile_insert(fn);
						if((fn=fn.get_oth())!=null) updfile_insert(fn);
					}
					return false;
					});
		}
		public void runcmd(string _cmd,Gtk.TreeSelection s){
			Gtk.TreeIter iter;
			string fn;
			s.get_selected(null,out iter);
			get(iter,Col.FN,out fn);
			Posix.system(_cmd+" \""+fn+"\""+"\n");
		}
		public uint get_nupdfile(){ return updfile.size(); }
		private void read_find(string fn,bool _diff=false){
			var hpa=new GLib.HashTable<string,FileNode>(str_hash,str_equal);
			var fi=File.new_for_path(fn);
			try{
				var dis=new DataInputStream(fi.read());
				string line;
				while((line=dis.read_line(null))!=null){
					int px=line.index_of(" ");
					if(px>=0){
						int64 si; si=int64.parse(line.substring(0,px))*1024;
						string name=line.substring(px+1);
						string dn=name.substring(0,name.last_index_of("/"));
						FileNode? pa;
						if(!hpa.lookup_extended(dn,null,out pa)) pa=null;
						hpa.set(name,new FileNode("%s/%s".printf(fn,name),this,pa,_diff,si));
					}
				}
			}catch(Error e){
				stdout.printf("Error: in file mode init: %s\n",e.message);
			}
		}
	}

	public class FileNode {
		private GLib.File     fi;
		private FileTree      ft;
		private FileMonitor   fm;
		private Gtk.TreeIter? it=null;
		private GLib.HashTable<string,FileNode> ch;
		private FileNode?     pa;
		private int64         si=0;
		private int64         ssi=0;
		private bool          ssichg=false;
		private bool          vis=false;
		public  bool          del=false;
		private bool          dsec=false;
		private bool          fix=false;
		private FileNode?     doth=null;
		private int           act=0;
		private uint          ch_act=0;
		public static uint    nfn=0;
		private string        fsys;
		private GLib.FileType ftype=FileType.UNKNOWN;
		public FileNode(string _fn,FileTree _ft,FileNode? _pa=null,bool _dsec=false,int64 fix_si=-1){
			nfn++;
			fi=File.new_for_path(_fn);
			ft=_ft;
			pa=_pa;
			dsec=_dsec;

			#if DEBUG
			Debug.debug("create %s".printf(fi.get_path()));
			#endif
			string dfn=fi.get_basename();
			if(pa!=null) dfn="%s/%s".printf(ft.get_str(pa.it,FileTree.Col.DFN),dfn);
			doth=ft.fns.lookup(dfn);
			if(!dsec && doth!=null && !doth.dsec){
				int i;
				for(i=0;doth!=null;i++) doth=ft.fns.lookup("%s%i".printf(dfn,i));
				dfn="%s%i".printf(dfn,i);
			}
			if(doth==null && dsec && pa==null && ft.iter_n_children(null)==1){
				Gtk.TreeIter dit;
				if(ft.get_iter_first(out dit)){
					string dfn2=ft.get_str(dit,FileTree.Col.DFN);
					doth=ft.fns.lookup(dfn2);
					if(doth!=null){
						ft.set(doth.it,FileTree.Col.BN,"%s (%s)".printf(dfn2,dfn));
						dfn=dfn2;
					}
				}
			}

			if(doth!=null){
				it=doth.it;
				doth.doth=this;
			}else{
				if(pa==null) ft.append(out it,null);
				else ft.append(out it,pa.it);
				ft.set(it,FileTree.Col.DFN,dfn);
			}
			if(doth==null || !dsec){
				ft.set(it,
					FileTree.Col.FN,_fn,
					FileTree.Col.BN,fi.get_basename(),
					FileTree.Col.ACT,-1);
				ft.fns.set(dfn,this);
			}

			ch=new GLib.HashTable<string,FileNode>(str_hash,str_equal);

			if(fix_si>=0){
				fix=true;
				updssi(fix_si-si);
				si=fix_si;
			}
		}
		public FileNode  get_prim(){ return  dsec && doth!=null ? doth : this; }
		public FileNode  get_sec (){ return !dsec && doth!=null ? doth : this; }
		public FileNode? get_oth (){ return  doth; }
		public Gtk.TreeIter get_it(){ return it; }
		public int64 get_ssi(){ return ssi; }
		public bool get_ssichg(){ bool ret=ssichg; ssichg=false; return ret; }
		public bool is_fix(){ return fix; }
		public string rnd_ssi(){
			if(!ft.isdiff()) return "%s".printf(rndsi(ssi));
			if(doth!=null) return "%s (%s)".printf(rndsi(ssi),rndsi(doth.ssi-ssi,true));
			if(dsec) return "# (%s)".printf(rndsi(ssi,true));
			return "%s (#)".printf(rndsi(ssi));
		}
		public int rnd_spi(){
			int64 ps=ssi,s=ssi;
			if(pa!=null){
				ps=pa.ssi;
				if(doth!=null && pa.doth!=null){
					s=(s-doth.ssi).abs();
					ps=(ps-pa.doth.ssi).abs();
				}
			}
			int v=0;
			if(ps!=0) v=(int)(s*100/ps);
			if(v>100) v=100;
			if(v<0) v=0;
			return v;
		}
		private void updssi(int64 chg){
			ssi+=chg;
			ssichg=true;
			if(vis) ch.find((fn,fc)=>{ if(fc.vis) ft.upddpl.insert(fc.get_prim()); return false; });
			if(pa!=null) pa.updssi(chg);
			else if(vis) ft.upddpl.insert(this);
		}
		private string rndsi(int64 _si,bool av=false){
			if(_si==0) return "0";
			string ext[5]={"k","M","G","T"};
			double si=_si;
			int ei;
			string v="";
			if(si<0){ v="-"; si*=-1; }
			else if(av) v="+";
			si/=1024;
			for(ei=0;si>=1000 && ei<ext.length;ei++) si/=1024;
			int num=si<10?1:0;
			return ("%s%."+num.to_string()+"f"+ext[ei]).printf(v,si);
		}
		private string rndtime(TimeVal time){ return Time.local(time.tv_sec).format("%x %H:%M"); }
		private string rndmode(uint mode){
			bool us=(mode>>11)%2==1;
			bool gs=(mode>>10)%2==1;
			bool ot=(mode>>9)%2==1;
			return "%c%c%c%c%c%c%c%c%c".printf(
				(mode>>8)%2==1?'r':'-',(mode>>7)%2==1?'w':'-',(mode>>6)%2==1?(us?'s':'x'):(us?'S':'-'),
				(mode>>5)%2==1?'r':'-',(mode>>4)%2==1?'w':'-',(mode>>3)%2==1?(gs?'s':'x'):(gs?'S':'-'),
				(mode>>2)%2==1?'r':'-',(mode>>1)%2==1?'w':'-',(mode>>0)%2==1?(ot?'t':'x'):(ot?'T':'-')
			);
		}
		static const string file_attr=
			FileAttribute.STANDARD_NAME+","+
			FileAttribute.STANDARD_TYPE+","+
			FileAttribute.STANDARD_ALLOCATED_SIZE+","+
			FileAttribute.OWNER_USER+","+
			FileAttribute.OWNER_GROUP+","+
			FileAttribute.TIME_MODIFIED+","+
			FileAttribute.UNIX_MODE+","+
			FileAttribute.STANDARD_SIZE+","+
			FileAttribute.ID_FILESYSTEM;
		private void updinfo(FileInfo? i){
			int64 nsi=0;
			#if DEBUG
			Debug.debug("updinfo %s".printf(fi.get_path()));
			#endif
			if(i!=null){
				ftype=i.get_file_type();
				TimeVal mtime=i.get_modification_time();
				if(!dsec) ft.set(it,
					FileTree.Col.MTIME,rndtime(mtime),
					FileTree.Col.MODE, rndmode(i.get_attribute_uint32(FileAttribute.UNIX_MODE)),
					FileTree.Col.USER, i.get_attribute_string(FileAttribute.OWNER_USER),
					FileTree.Col.GROUP,i.get_attribute_string(FileAttribute.OWNER_GROUP),
					FileTree.Col.SIZE, rndsi(i.get_size()));
				if(ft.fsys_only) fsys=i.get_attribute_string(FileAttribute.ID_FILESYSTEM);
				nsi=(int64)i.get_attribute_uint64(FileAttribute.STANDARD_ALLOCATED_SIZE);
			}
			updssi(nsi-si);
			si=nsi;
		}
		public void updfile(int depth){
			if(del) return;
			#if DEBUG
			Debug.debug("updfile start %s (depth %i)".printf(fi.get_path(),depth));
			#endif
			Timer.timer(1,-1);
			GLib.FileQueryInfoFlags flags = pa==null ? GLib.FileQueryInfoFlags.NONE : GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS;
			if(ftype==FileType.UNKNOWN){
				try{ updinfo(fi.query_info(file_attr,flags,null)); }
				catch(GLib.Error e){
					stdout.printf("Error query file %s: %s",fi.get_path(),e.message);
					updinfo(null);
				}
			}
			Timer.timer(1,0);
			if(ftype==GLib.FileType.DIRECTORY){
				fi.enumerate_children_async.begin(file_attr,GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS,Priority.DEFAULT,null,(obj,res)=>{
					GLib.HashTable<string,FileNode> nch=new GLib.HashTable<string,FileNode>(str_hash,str_equal);
					try{
						var en=fi.enumerate_children_async.end(res);
						FileInfo fich;
						while((fich=en.next_file())!=null){
							FileNode? fn=ch.lookup(fich.get_name());
							if(ft.fsys_only){
								string _fsys=fich.get_attribute_string(FileAttribute.ID_FILESYSTEM);
								if(_fsys!=fsys) continue;
							}
							int _depth=depth<0?-1:depth-1;
							if(fn==null){
								_depth=-1;
								fn=new FileNode(fi.get_path()+"/"+fich.get_name(),ft,this,dsec);
							}else ch.remove(fich.get_name());
							fn.updinfo(fich);
							if(depth!=0) ft.updfile_insert(fn,_depth);
							nch.insert(fich.get_name(),fn);
						}
					}catch(GLib.Error e){ stdout.printf("Error in reading dir %s: %s\n",fi.get_path(),e.message); }
					ch.find((fn,fc)=>{
						if(!fc.del){
							#if DEBUG
							Debug.debug("kill %s".printf(fc.fi.get_path()));
							#endif
							updssi(-fc.ssi);
							fc.kill();
						}
						return false;
					});
					ch=nch;
				});
				Timer.timer(1,1);
				try{
					fm=fi.monitor_directory(FileMonitorFlags.NONE,null);
					fm.changed.connect((file,otherfile,evtype)=>{
						ft.updfile_insert(this,1);
					});
				}catch(GLib.IOError e){ stdout.printf("Error monitor dir %s: %s",fi.get_path(),e.message); }
			}
			Timer.timer(1,2);
			set_chact(-1);
			Timer.timer(1,3);
			#if DEBUG
			Debug.debug("updfile end %s".printf(fi.get_path()));
			#endif
		}
		private void kill(){
			nfn--;
			del=true;
			ch.find((fn,fc)=>{ fc.kill(); return false; });
			if(doth!=null){
				ft.fns.set(ft.get_str(it,FileTree.Col.DFN),doth);
				doth.doth=null;
			}else{
				ft.fns.remove(ft.get_str(it,FileTree.Col.DFN));
				ft.remove(ref it);
			}
		}
		public bool get_vis(){ return vis; }
		public void set_vis(){ vis=true; set_chact(); }
		private void set_chact(int ch=0){
			bool init=false;
			if(ch<0){
				if(ch_act>-ch) ch_act+=ch;
				else{
					ch_act=0;
					if(vis) ft.set(it,FileTree.Col.ACT,-1);
					if(pa!=null) pa.set_chact(-1);
				}
			}else if(ch>0){
				if(ch_act==0){
					if(vis) init=true;
					if(pa!=null) pa.set_chact(1);
				}
				ch_act+=ch;
			}else /*ch==0*/ if(vis && ch_act!=0) init=true;
			if(init){ on_act(); GLib.Timeout.add(500,on_act); }
			#if DEBUG
			Debug.debug("chact   %s (%2i->%u)".printf(fi.get_path(),ch,ch_act));
			#endif
		}
		private bool on_act(){
			#if DEBUG
			Debug.debug("onact   %s (    %u)".printf(fi.get_path(),ch_act));
			#endif
			if(ch_act==0) return false;
			ft.set(it,FileTree.Col.ACT,act++);
			return true;
		}
		public void on_upd(){
			#if DEBUG
			Debug.debug("on_upd %s".printf(fi.get_path()));
			#endif
			set_chact(1);
		}
	}
	public class ProgressBar : Gtk.ProgressBar, Gtk.Buildable {
		private FileTree ft;
		public void parser_finished(Gtk.Builder builder){
			ft=builder.get_object("filetree") as FileTree;
			GLib.Timeout.add(500,on_upd);
		}
		private bool on_upd(){
			uint nu=ft.get_nupdfile();
			visible=nu!=0;
			if(nu!=0){
				uint nf=FileNode.nfn;
				nu=nf-nu;
				fraction=(double)nu/(double)nf;
				text="%u/%u".printf(nu,nf);
			}
			return true;
		}
	}
	public class Timer {
		private static Posix.timespec tsl[5];
		private static double timers[50];
		public static void timer(int x,int id){
			Posix.timespec ts;
			Posix.clock_gettime(Posix.CLOCK_PROCESS_CPUTIME_ID,out ts);
			if(id>=0) timers[x*10+id]+=(double)(ts.tv_sec-tsl[x].tv_sec)*1000+(double)(ts.tv_nsec-tsl[x].tv_nsec)/1000000;
			if(id==-2){
				int i;
				stdout.printf("[%i]",x);
				for(i=0;i<10;i++){ stdout.printf(" %i:%.0f",i,timers[x*10+i]); timers[x*10+i]=0; }
				stdout.printf("\n");
			}
			tsl[x]=ts;
		}
	}
	#if DEBUG
	public class Debug {
		private static int level=0;
		private static double dfirst=0;
		public static void inc_level(){ level++; }
		public static void debug(string msg){
			if(level>0){
				Posix.timespec ts;
				Posix.clock_gettime(Posix.CLOCK_REALTIME,out ts);
				double t = (double)ts.tv_sec + (double)ts.tv_nsec/1e9;
				if(dfirst==0) dfirst=t;
				stdout.printf("%7.3f %s\n",t-dfirst,msg);
			}
		}
	}
	#endif
}
