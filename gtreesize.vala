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
		private GLib.HashTable<FileNode,FileNode> hst=new GLib.HashTable<FileNode,FileNode>(null,null);
		private CheckFunc check;
		public Queue(CheckFunc _check){ check=_check; }
		public void insert(FileNode fn){ if(!hst.contains(fn)){ hst.insert(fn,fn); check(); } }
		public bool empty(){ return hst.size()==0; }
		public bool pop(out FileNode fn){
			fn=null;
			if(empty()) return false;
			fn=hst.find((k,v)=>{ return true; });
			hst.remove(fn);
			return true;
		}
	}

	public class FileTree : Gtk.TreeStore, Gtk.TreeModel, Gtk.Buildable {
		public enum Col { FN,DFN,SSI,RSSI,RSPI,ACT,BN,MTIME,MODE,USER,GROUP,SIZE,NUM }
		public signal void setcur(bool wait);
		public Queue upddpl;
		public Queue updfile;
		public GLib.HashTable<string,FileNode> fns=new GLib.HashTable<string,FileNode>(str_hash,str_equal);
		private bool updateon=false;
		private time_t lastupd=0;
		private Gtk.FileChooserDialog fc;
		private bool diff=false;
		public void parser_finished(Gtk.Builder builder){
			fc=builder.get_object("fc") as Gtk.FileChooserDialog;
			upddpl=new Queue(updcheck);
			updfile=new Queue(updcheck);
			set_sort_column_id(Col.SSI,Gtk.SortType.DESCENDING);
			if(args.length<2) seldir();
			else if(args.length==4 && args[1]=="-d"){
				adddir(args[2]);
				adddir(args[3],true);
			}else for(int i=1;i<args.length;i++) adddir(args[i]);
		}
		protected void diffdir(){ seldir(true); }
		protected void seldir(bool _diff=false){
			if(fc.run()==Gtk.ResponseType.ACCEPT) adddir(fc.get_filename(),_diff);
			fc.hide();
		}
		public void adddir(string dirname,bool _diff=false){
			updfile.insert(new FileNode(dirname,this,null,_diff));
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
				if(it2fn(iter,out fn) && !fn.vis){ upddpl.insert(fn); fn.vis=true; }
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
			if(!upddpl.empty() && (updfile.empty() || tchg))
				while(upddpl.pop(out fn)){
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
			else if(!updfile.empty()) if(updfile.pop(out fn)) fn.updfile();
			bool nupdateon=!(updfile.empty() && upddpl.empty());
			Timer.timer(0,0);
			if(nupdateon!=updateon) setcur(nupdateon);
			if(updateon && !nupdateon){ Timer.timer(1,-2); Timer.timer(0,-2); }
			return updateon=nupdateon;
		}
		public void updcheck(){ if(!updateon) GLib.Idle.add(update); }
		public void refresh(Gtk.TreeSelection? s){
			if(s!=null) s.selected_foreach((tm,tp,it)=>{
					FileNode fn;
					if(it2fn(it,out fn)){
						updfile.insert(fn);
						if((fn=fn.get_oth())!=null) updfile.insert(fn);
					}
					});
			else base.foreach((tm,tp,it)=>{
					FileNode fn;
					if(it2fn(it,out fn)){
						updfile.insert(fn);
						if((fn=fn.get_oth())!=null) updfile.insert(fn);
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
		public  bool          vis=false;
		public  bool          del=false;
		private bool          dsec=false;
		private FileNode?     doth=null;
		private int           act=0;
		private uint          ch_act=1;
		public FileNode(string _fn,FileTree _ft,FileNode? _pa=null,bool _dsec=false){
			fi=File.new_for_path(_fn);
			ft=_ft;
			pa=_pa;
			dsec=_dsec;

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
						ft.set(doth.it,FileTree.Col.BN,"%s (%s)".printf(dfn,dfn2));
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
					FileTree.Col.BN,fi.get_basename());
				ft.fns.set(dfn,this);
			}

			ch=new GLib.HashTable<string,FileNode>(str_hash,str_equal);

			GLib.Timeout.add(500,on_act);
		}
		~FileNode(){
			if(pa!=null) pa.updssi(-si);
			if(doth!=null) doth.doth=null;
			else ft.remove(ref it);
		}
		public FileNode  get_prim(){ return  dsec && doth!=null ? doth : this; }
		public FileNode  get_sec (){ return !dsec && doth!=null ? doth : this; }
		public FileNode? get_oth (){ return  doth; }
		public Gtk.TreeIter get_it(){ return it; }
		public int64 get_ssi(){ return ssi; }
		public bool get_ssichg(){ bool ret=ssichg; ssichg=false; return ret; }
		public string rnd_ssi(){
			if(doth==null) return rndsi(ssi);
			return "%s (%s)".printf(rndsi(ssi),rndsi(doth.ssi-ssi,true));
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
		public void updfile(){
			if(del) return;
			int64 nsi=0;
			Timer.timer(1,-1);
			try{
				GLib.FileQueryInfoFlags flags = pa==null ? GLib.FileQueryInfoFlags.NONE : GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS;
				FileInfo i=fi.query_info(FileAttribute.STANDARD_ALLOCATED_SIZE+","+FileAttribute.OWNER_USER+","+FileAttribute.OWNER_GROUP+","+FileAttribute.TIME_MODIFIED+","+FileAttribute.UNIX_MODE+","+FileAttribute.STANDARD_SIZE,flags,null);
				nsi=(int64)i.get_attribute_uint64(FileAttribute.STANDARD_ALLOCATED_SIZE);
				TimeVal mtime=i.get_modification_time();
				if(!dsec) ft.set(it,
					FileTree.Col.MTIME,rndtime(mtime),
					FileTree.Col.MODE, rndmode(i.get_attribute_uint32(FileAttribute.UNIX_MODE)),
					FileTree.Col.USER, i.get_attribute_string(FileAttribute.OWNER_USER),
					FileTree.Col.GROUP,i.get_attribute_string(FileAttribute.OWNER_GROUP),
					FileTree.Col.SIZE, rndsi(i.get_size()));
				Timer.timer(1,0);
				if(fi.query_file_type(flags,null)==GLib.FileType.DIRECTORY){
					var en=fi.enumerate_children (FileAttribute.STANDARD_NAME,flags);
					FileInfo fich;
					GLib.HashTable<string,FileNode> nch=new GLib.HashTable<string,FileNode>(str_hash,str_equal);
					while((fich=en.next_file())!=null){
						FileNode? fn=ch.lookup(fich.get_name());
						if(fn==null) fn=new FileNode(fi.get_path()+"/"+fich.get_name(),ft,this,dsec);
						else ch.remove(fich.get_name());
						ft.updfile.insert(fn);
						nch.insert(fich.get_name(),fn);
					}
					ch.find((fn,fc)=>{ updssi(-fc.ssi); fc.kill(); ft.remove(ref fc.it); return false; });
					ch=nch;
				}
				Timer.timer(1,1);
				if(fi.query_file_type(flags,null)==GLib.FileType.DIRECTORY){
					fm=fi.monitor_directory(FileMonitorFlags.NONE,null);
					fm.changed.connect((file,otherfile,evtype)=>{
						ft.updfile.insert(this);
					});
				}
				Timer.timer(1,2);
			}catch(Error e){
				nsi=0;
			}
			updssi(nsi-si);
			si=nsi;
			ch_act=ch.size();
			Timer.timer(1,3);
		}
		private void kill(){
			del=true;
			ch.find((fn,fc)=>{ fc.kill(); return false; });
		}
		private bool on_act(){
			if(ch_act==0){
				if(pa!=null && pa.ch_act!=0) pa.ch_act--;
				ft.set(it,FileTree.Col.ACT,-1);
				return false;
			}
			ft.set(it,FileTree.Col.ACT,act++);
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
}
