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
	public static int main (string[] args)
	{
		Gtk.init(ref args);
		GLib.Environment.set_application_name("gTreesize");
		var tmp=new Treesize(); tmp.destroy();
		var ts=Treesize.create(args);
		ts.show_all();
		Gtk.main();
		return 0;
	}
	public class Treesize : Gtk.Window, Gtk.Buildable {
		private GLib.List<Gtk.MenuItem> mu_one_sel;
		private const Gtk.TargetEntry[] _dragtarget = { {"text/plain",0,0} };
		private Gdk.Cursor cur_def;
		private Gdk.Cursor cur_wait;
		public static Treesize create(string[] args){
			builder.expose_object("treesize-args",args);
			var builder=new Gtk.Builder.from_resource("/org/gtreesize/ui/treesize.xml");
			var ts=builder.get_object("treesize") as Treesize;
			var tv=builder.get_object("treesize-tv") as Gtk.TreeView;
			tv.model=new FileTree(args);
			if(args.length<2) ts.on_add();
			return builder.get_object("treesize") as Treesize;
		}
		public void parser_finished(Gtk.Builder builder){
			var args=builder.get_object("treesize-args") as string[];
			builder.connect_signals(this);
		}
		public Treesize(){}
/*		public Treesize(string[] args){
			// TreeView
			tm.setcur.connect((wait)=>{get_window().set_cursor(wait?cur_wait:cur_def);});
			tv.enable_model_drag_source(Gdk.ModifierType.BUTTON1_MASK,_dragtarget,Gdk.DragAction.COPY);
			tv.drag_data_get.connect((wdg,ctx,sdat,info,time)=>{
				Gtk.TreeIter iter; tv.get_selection().get_selected(null,out iter);
				string fn; tm.get(iter,1,out fn);
				uchar[] data=(uchar[])fn.to_utf8(); data.length++;
				sdat.set(Gdk.Atom.intern(_dragtarget[0].target,true),8,data);
			});
			// Menu
			var fc=new Gtk.FileChooserDialog("Add Directory",this,Gtk.FileChooserAction.SELECT_FOLDER,
				"gtk-cancel",Gtk.ResponseType.CANCEL,"gtk-add",Gtk.ResponseType.ACCEPT);
			mu_one_sel=new GLib.List<Gtk.MenuItem>();
			var mu=new Gtk.Menu();
			mu_one_sel.prepend(createmi("gtk-open",mu)); mu_one_sel.first().data.activate.connect(()=>{ tm.runcmd("xdg-open",tv.get_selection()); });
			mu_one_sel.prepend(createmi("gtk-delete",mu)); mu_one_sel.first().data.activate.connect(()=>{ tm.runcmd("rm -rf",tv.get_selection()); });
			createmi("gtk-refresh",mu).activate.connect(()=>{ tm.refresh(tv.get_selection()); });
			mu.append(new Gtk.SeparatorMenuItem());
			createmi("gtk-add",mu).activate.connect(()=>{ tm.seldir(fc); });
			createmi("gtk-quit",mu).activate.connect(Gtk.main_quit);
			mu.show_all();
			tv.button_press_event.connect((ev)=>{ if(ev.button!=3) return false; mu.popup(null,null,null,ev.button,Gtk.get_current_event_time()); return true; });
			tv.get_selection().changed.connect(on_sel_chg);
			on_sel_chg(tv.get_selection());
			// Window
//			key_press_event.connect((ev)=>{ if(ev.keyval==113 && ev.state==Gdk.ModifierType.CONTROL_MASK) Gtk.main_quit(); return true; });
			// Cursor
			cur_def=get_window().get_cursor();
			cur_wait=new Gdk.Cursor(Gdk.CursorType.WATCH);
			// Finish
		}*/
		protected void on_refresh(){
			stdout.printf("HALLO 1\n");
			//tm.refresh(null);
		}
		protected void on_add(){
			stdout.printf("HALLO\n");
			//tm.seldir(fc)
		}
		private Gtk.MenuItem createmi(string stock_id,Gtk.Menu mu){
			var mi=new Gtk.ImageMenuItem.from_stock(stock_id,null);
			mu.append(mi);
			return mi;
		}
		private void on_sel_chg(Gtk.TreeSelection s){
			int n=s.count_selected_rows();
			foreach(var i in mu_one_sel) i.sensitive=(n==1);
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

	public class FileTree : Gtk.TreeStore, Gtk.TreeModel {
		public signal void setcur(bool wait);
		public Queue upddpl;
		public Queue updfile;
		public GLib.HashTable<int,FileNode> fns=new GLib.HashTable<int,FileNode>(null,null);
		private bool updateon=false;
		private time_t lastupd=0;
		public FileTree(string[] args){
			upddpl=new Queue(updcheck);
			updfile=new Queue(updcheck);
			set_column_types(new GLib.Type[11] {typeof(int),typeof(string),typeof(int64),typeof(string),typeof(int),typeof(string),typeof(string),typeof(string),typeof(string),typeof(string),typeof(string)});
			set_sort_column_id(2,Gtk.SortType.DESCENDING);
			for(int i=1;i<args.length;i++) adddir(args[i]);
		}
		public void seldir(Gtk.FileChooserDialog fc){
			if(fc.run()==Gtk.ResponseType.ACCEPT) adddir(fc.get_filename());
			fc.hide();
		}
		private void adddir(string dirname){ updfile.insert(new FileNode(dirname,this)); }
		private bool it2fn(Gtk.TreeIter it,out FileNode? fn){
			GLib.Value vid; base.get_value(it,0,out vid);
			int id=vid.get_int();
			return (fn= id==0 ? null : fns.lookup(id))!=null;
		}
		public void get_value(Gtk.TreeIter iter,int column,out GLib.Value val){
			if(column<3 || column>4){
				base.get_value(iter,column,out val);
			}else{
				FileNode fn;
				if(it2fn(iter,out fn) && !fn.vis){ upddpl.insert(fn); fn.vis=true; }
				switch(column){
				case 3:
					val=Value(typeof(string));
					if(fn!=null) val.set_string(fn.rnd_ssi());
				break;
				case 4:
					val=Value(typeof(int));
					if(fn!=null) val.set_int(fn.rnd_spi());
				break;
				}
			}
		}
		public bool update(){
			Timer.timer(0,-1);
			time_t t=time_t();
			bool tchg=t!=lastupd;
			lastupd=t;
			FileNode fn;
			if(!upddpl.empty() && (updfile.empty() || tchg))
				while(upddpl.pop(out fn)){
					if(!fn.del){
						if(fn.get_ssichg()) set(fn.get_it(),2,fn.get_ssi());
						else row_changed(get_path(fn.get_it()),fn.get_it());
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
					if(it2fn(it,out fn)) updfile.insert(fn);
					});
			else base.foreach((tm,tp,it)=>{
					FileNode fn;
					if(it2fn(it,out fn)) updfile.insert(fn);
					return false;
					});
		}
		public void runcmd(string _cmd,Gtk.TreeSelection s){
			Gtk.TreeIter iter;
			string fn;
			s.get_selected(null,out iter);
			get(iter,1,out fn);
			Posix.system(_cmd+" \""+fn+"\""+"\n");
		}
	}

	public class FileNode {
		private GLib.File    fi;
		private FileTree     ft;
		private Gtk.TreeIter it;
		private GLib.HashTable<string,FileNode> ch;
		private FileNode?    pa;
		private int64        si=0;
		private int64        ssi=0;
		private bool         ssichg=false;
		public  bool         vis=false;
		public  bool         del=false;
		public FileNode(string _fn,FileTree _ft,FileNode? _pa=null){
			fi=File.new_for_path(_fn);
			ft=_ft;
			pa=_pa;
			if(pa==null) ft.append(out it,null);
			else ft.append(out it,pa.it);
			ft.set(it,0,ft.fns.size()+1,1,_fn,5,fi.get_basename());
			ft.fns.set((int)ft.fns.size()+1,this);
			ch=new GLib.HashTable<string,FileNode>(null,null);
		}
		~FileNode(){
			if(pa!=null) pa.updssi(-si);
			ft.remove(ref it);
		}
		public Gtk.TreeIter get_it(){ return it; }
		public int64 get_ssi(){ return ssi; }
		public bool get_ssichg(){ bool ret=ssichg; ssichg=false; return ret; }
		public string rnd_ssi(){ return rndsi(ssi); }
		public int rnd_spi(){ return pa!=null?(int)(pa.ssi==0?0:ssi*100/pa.ssi):100; }
		private void updssi(int64 chg){
			ssi+=chg;
			ssichg=true;
			if(vis) ch.find((fn,fc)=>{ if(fc.vis) ft.upddpl.insert(fc); return false; });
			if(pa!=null) pa.updssi(chg);
			else if(vis) ft.upddpl.insert(this);
		}
		private string rndsi(int64 _si){
			if(_si==0) return "0";
			string ext[5]={"k","M","G","T"};
			double si=_si;
			int ei;
			si/=1024;
			for(ei=0;si>=1000 && ei<ext.length;ei++) si/=1024;
			int num=si<10?1:0;
			return ("%."+num.to_string()+"f"+ext[ei]).printf(si);
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
				ft.set(it,
					6,rndtime(mtime),
					7,rndmode(i.get_attribute_uint32(FileAttribute.UNIX_MODE)),
					8,i.get_attribute_string(FileAttribute.OWNER_USER),
					9,i.get_attribute_string(FileAttribute.OWNER_GROUP),
					10,rndsi(i.get_size()));
				Timer.timer(1,0);
				if(fi.query_file_type(flags,null)==GLib.FileType.DIRECTORY){
					var en=fi.enumerate_children (FileAttribute.STANDARD_NAME,flags);
					FileInfo fich;
					GLib.HashTable<string,FileNode> nch=new GLib.HashTable<string,FileNode>(str_hash,str_equal);
					while((fich=en.next_file())!=null){
						FileNode? fn=ch.lookup(fich.get_name());
						if(fn==null) fn=new FileNode(fi.get_path()+"/"+fich.get_name(),ft,this);
						else ch.remove(fich.get_name());
						ft.updfile.insert(fn);
						nch.insert(fich.get_name(),fn);
					}
					ch.find((fn,fc)=>{ updssi(-fc.ssi); fc.kill(); ft.remove(ref fc.it); return false; });
					ch=nch;
				}
				Timer.timer(1,1);
//				var fm=fi.monitor(FileMonitorFlags.NONE); /* TODO: monitor_directory */
//				fm.changed.connect((file,otherfile,evtype)=>{
//					ft.updfile.insert(this);
//				});
				Timer.timer(1,2);
			}catch(Error e){
				nsi=0;
			}
			updssi(nsi-si);
			si=nsi;
			Timer.timer(1,3);
		}
		private void kill(){
			del=true;
			ch.find((fn,fc)=>{ fc.kill(); return false; });
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
