namespace Treesize {
	public static int main (string[] args)
	{
		Gtk.init(ref args);
		GLib.Environment.set_application_name("Treesize");
		new Treesize(args);
		Gtk.main();
		return 0;
	}
	public class Treesize : Gtk.Window {
		private GLib.List<Gtk.MenuItem> mu_one_sel;
		private const Gtk.TargetEntry[] _dragtarget = { {"text/plain",0,0} };
		public Treesize(string[] args){
			// CellRenderer
			var trs=new Gtk.CellRendererText();
			var trp=new Gtk.CellRendererProgress();
			var trf=new Gtk.CellRendererText();
			var tc=new Gtk.TreeViewColumn();
			tc.set_title("File");
			tc.pack_start(trs,false); tc.add_attribute(trs,"text",2);
			tc.pack_start(trp,false); tc.add_attribute(trp,"value",3);
			tc.pack_start(trf,false); tc.add_attribute(trf,"text",4);
			// TreeView
			var tm=new FileTree(args);
			var tv=new Gtk.TreeView.with_model(tm);
			tv.append_column(tc);
			tv.append_column(new Gtk.TreeViewColumn.with_attributes("MTime",new Gtk.CellRendererText(),"text",5));
			tv.append_column(new Gtk.TreeViewColumn.with_attributes("Mode",new Gtk.CellRendererText(),"text",6));
			tv.append_column(new Gtk.TreeViewColumn.with_attributes("Owner",new Gtk.CellRendererText(),"text",7));
			tv.append_column(new Gtk.TreeViewColumn.with_attributes("Group",new Gtk.CellRendererText(),"text",8));
			tv.append_column(new Gtk.TreeViewColumn.with_attributes("Size",new Gtk.CellRendererText(),"text",9));
			tv.enable_model_drag_source(Gdk.ModifierType.BUTTON1_MASK,_dragtarget,Gdk.DragAction.COPY);
			tv.drag_data_get.connect((wdg,ctx,sdat,info,time)=>{
				Gtk.TreeIter iter; tv.get_selection().get_selected(null,out iter);
				string fn; tm.get(iter,0,out fn);
				uchar[] data=(uchar[])fn.to_utf8(); data.length++;
				sdat.set(Gdk.Atom.intern(_dragtarget[0].target,true),8,data);
			});
			// ScrolledWindow
			var sc=new Gtk.ScrolledWindow(null,null);
			sc.add_with_viewport(tv);
			// Menu
			var fc=new Gtk.FileChooserDialog("Add Directory",this,Gtk.FileChooserAction.SELECT_FOLDER,
				Gtk.STOCK_CANCEL,Gtk.ResponseType.CANCEL,Gtk.STOCK_ADD,Gtk.ResponseType.ACCEPT);
			mu_one_sel=new GLib.List<Gtk.MenuItem>();
			var mu=new Gtk.Menu();
			mu_one_sel.prepend(createmi(Gtk.STOCK_OPEN,mu)); mu_one_sel.first().data.activate.connect(()=>{ tm.runcmd("xdg-open",tv.get_selection()); });
			mu_one_sel.prepend(createmi(Gtk.STOCK_DELETE,mu)); mu_one_sel.first().data.activate.connect(()=>{ tm.runcmd("rm -rf",tv.get_selection()); });
			mu.append(new Gtk.SeparatorMenuItem());
			createmi(Gtk.STOCK_ADD,mu).activate.connect(()=>{ tm.seldir(fc); });
			createmi(Gtk.STOCK_QUIT,mu).activate.connect(Gtk.main_quit);
			mu.show_all();
			tv.button_press_event.connect((ev)=>{ if(ev.button!=3) return false; mu.popup(null,null,null,ev.button,Gtk.get_current_event_time()); return true; });
			tv.get_selection().changed.connect(on_sel_chg);
			on_sel_chg(tv.get_selection());
			// Window
			add(sc);
			set_default_size(500,700);
			delete_event.connect((ev)=>{ Gtk.main_quit(); return true; });
			key_press_event.connect((ev)=>{ if(ev.keyval==113 && ev.state==Gdk.ModifierType.CONTROL_MASK) Gtk.main_quit(); return true; });
			show_all();
			if(args.length<2) tm.seldir(fc);
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
		private GLib.HashTable<FileNode,bool> hst=new GLib.HashTable<FileNode,bool>(null,null);
		private GLib.List<FileNode> lst=new GLib.List<FileNode>();
		private CheckFunc check;
		public Queue(CheckFunc _check){ check=_check; }
		public void insert(FileNode fn){ if(!hst.lookup_extended(fn,null,null)){ hst.insert(fn,true); lst.append(fn); check(); } }
		public bool empty(){ return hst.size()==0; }
		public bool pop(out FileNode fn){
			if(empty()) return false;
			fn=lst.first().data;
			lst.remove_link(lst.first());
			hst.remove(fn);
			return true;
		}
	}

	public class FileTree : Gtk.TreeStore {
		public Queue upddpl;
		public Queue updfile;
		private bool updateon=false;
		private time_t lastupd=0;
		public FileTree(string[] args){
			upddpl=new Queue(updcheck);
			updfile=new Queue(updcheck);
			set_column_types(new GLib.Type[10] {typeof(string),typeof(int64),typeof(string),typeof(int),typeof(string),typeof(string),typeof(string),typeof(string),typeof(string),typeof(string)});
			set_sort_column_id(1,Gtk.SortType.DESCENDING);
			for(int i=1;i<args.length;i++) adddir(args[i]);
		}
		public void seldir(Gtk.FileChooserDialog fc){
			if(fc.run()==Gtk.ResponseType.ACCEPT) adddir(fc.get_filename());
			fc.hide();
		}
		private void adddir(string dirname){ updfile.insert(new FileNode(dirname,this)); }
		public bool update(){
			time_t t=time_t();
			bool tchg=t!=lastupd;
			lastupd=t;
			FileNode fn;
			if(!upddpl.empty() && (updfile.empty() || tchg)){
				while(upddpl.pop(out fn)) fn.upddpl();
			}else if(!updfile.empty()) if(updfile.pop(out fn)) fn.updfile();
			return updateon=!(updfile.empty() && upddpl.empty());
		}
		public void updcheck(){ if(!updateon) GLib.Idle.add(update); }
		public void runcmd(string _cmd,Gtk.TreeSelection s){
			Gtk.TreeIter iter;
			string fn;
			s.get_selected(null,out iter);
			get(iter,0,out fn);
			Posix.system(_cmd+" \""+fn+"\""+"\n");
		}
	}

	public class FileNode {
		private GLib.File    fi;
		private FileTree     ft;
		private Gtk.TreeIter it;
		private GLib.HashTable<string,FileNode> ch;
		private weak FileNode? pa;
		private int64          si=0;
		private int64          ssi=0;
		public FileNode(string _fn,FileTree _ft,FileNode? _pa=null){
			fi=File.new_for_path(_fn);
			ft=_ft;
			pa=_pa;
			if(pa==null) ft.append(out it,null);
			else ft.append(out it,pa.it);
			ft.set(it,0,_fn,4,fi.get_basename());
			ch=new GLib.HashTable<string,FileNode>(null,null);
			upddpl();
		}
		~FileNode(){
			if(pa!=null) pa.updssi(-si);
			ft.remove(it);
		}
		private void updssi(int64 chg){
			ssi+=chg;
			foreach(var fc in ch.get_values()) ft.upddpl.insert(fc);
			if(pa!=null) pa.updssi(chg);
			else ft.upddpl.insert(this);
		}
		public void upddpl(){ ft.set(it,1,ssi,2,rndsi(ssi),3,pa!=null?(pa.ssi==0?0:ssi*100/pa.ssi):100); }
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
			int64 nsi=0;
			try{
				GLib.FileQueryInfoFlags flags = pa==null ? GLib.FileQueryInfoFlags.NONE : GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS;
				FileInfo i=fi.query_info(FILE_ATTRIBUTE_STANDARD_ALLOCATED_SIZE+","+FILE_ATTRIBUTE_OWNER_USER+","+FILE_ATTRIBUTE_OWNER_GROUP+","+FILE_ATTRIBUTE_TIME_MODIFIED+","+FILE_ATTRIBUTE_UNIX_MODE+","+FILE_ATTRIBUTE_STANDARD_SIZE,flags,null);
				nsi=(int64)i.get_attribute_uint64(FILE_ATTRIBUTE_STANDARD_ALLOCATED_SIZE);
				TimeVal mtime;
				i.get_modification_time(out mtime);
				ft.set(it,5,rndtime(mtime));
				ft.set(it,6,rndmode(i.get_attribute_uint32(FILE_ATTRIBUTE_UNIX_MODE)));
				ft.set(it,7,i.get_attribute_string(FILE_ATTRIBUTE_OWNER_USER));
				ft.set(it,8,i.get_attribute_string(FILE_ATTRIBUTE_OWNER_GROUP));
				ft.set(it,9,rndsi(i.get_size()));
				if(fi.query_file_type(flags,null)==GLib.FileType.DIRECTORY){
					var en=fi.enumerate_children (FILE_ATTRIBUTE_STANDARD_NAME,flags);
					FileInfo fich;
					GLib.HashTable<string,FileNode> nch=new GLib.HashTable<string,FileNode>(str_hash,str_equal);
					while((fich=en.next_file())!=null){
						FileNode fn;
						if(!ch.lookup_extended(fich.get_name(),null,out fn))
							ft.updfile.insert(fn=new FileNode(fi.get_path()+"/"+fich.get_name(),ft,this));
						nch.insert(fich.get_name(),fn);
					}
					ch=nch;
				}
				var fm=fi.monitor(FileMonitorFlags.NONE); /* TODO: monitor_directory */
				fm.changed.connect((file,otherfile,evtype)=>{
					ft.updfile.insert(this);
				});
			}catch(Error e){
				nsi=0;
			}
			updssi(nsi-si);
			si=nsi;
		}
	}
}
