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
		public Treesize(string[] args){
			// CellRenderer
			var trs=new Gtk.CellRendererText();
			var trp=new Gtk.CellRendererProgress();
			var trf=new Gtk.CellRendererText();
			var tc=new Gtk.TreeViewColumn();
			tc.set_title("File");
			tc.pack_start(trs,false); tc.add_attribute(trs,"text",0);
			tc.pack_start(trp,false); tc.add_attribute(trp,"value",1);
			tc.pack_start(trf,false); tc.add_attribute(trf,"text",2);
			// TreeView
			var tm=new FileTree(args);
			var tv=new Gtk.TreeView.with_model(tm);
			tv.append_column(tc);
			tv.append_column(new Gtk.TreeViewColumn.with_attributes("MTime",new Gtk.CellRendererText(),"text",4));
			tv.append_column(new Gtk.TreeViewColumn.with_attributes("Mode",new Gtk.CellRendererText(),"text",5));
			tv.append_column(new Gtk.TreeViewColumn.with_attributes("Owner",new Gtk.CellRendererText(),"text",6));
			tv.append_column(new Gtk.TreeViewColumn.with_attributes("Group",new Gtk.CellRendererText(),"text",7));
			tv.append_column(new Gtk.TreeViewColumn.with_attributes("Size",new Gtk.CellRendererText(),"text",8));
			// ScrolledWindow
			var sc=new Gtk.ScrolledWindow(null,null);
			sc.add_with_viewport(tv);
			// Window
			add(sc);
			set_default_size(500,700);
			delete_event.connect((ev)=>{ Gtk.main_quit(); return true; });
			key_press_event.connect((ev)=>{ if(ev.keyval==113 && ev.state==Gdk.ModifierType.CONTROL_MASK) Gtk.main_quit(); return true; });
			show_all();
		}
	}

	public class FileTree : Gtk.TreeStore {
		private FileNode[] roots;
		private GLib.HashTable<FileNode,bool> upddpl;
		private GLib.HashTable<FileNode,bool> updfile;
		private time_t lastupd=0;
		public FileTree(string[] args){
			set_column_types(new GLib.Type[9] {typeof(string),typeof(int),typeof(string),typeof(int64),typeof(string),typeof(string),typeof(string),typeof(string),typeof(string)});
			set_sort_column_id(3,Gtk.SortType.DESCENDING);
			roots=new FileNode[args.length-1];
			upddpl=new GLib.HashTable<FileNode,bool>(null,null);
			updfile=new GLib.HashTable<FileNode,bool>(null,null);
			for(int i=1;i<args.length;i++)
				addfile(roots[i-1]=new FileNode(args[i],this));
		}

		public bool update(){
			time_t t=time_t();
			bool tchg=t!=lastupd;
			lastupd=t;
			if(upddpl.size()>0 && (updfile.size()==0 || tchg)){
				var hti=GLib.HashTableIter<FileNode,bool>(upddpl);
				FileNode fn; bool b;
				while(hti.next(out fn,out b)){
					hti.remove();
					fn.upddpl();
				}
				return true;
			}
			if(updfile.size()>0){
				var hti=GLib.HashTableIter<FileNode,bool>(updfile);
				FileNode fn; bool b;
				if(hti.next(out fn,out b)){
					hti.remove();
					fn.updfile();
					return true;
				}
			}
			return updfile.size()>0 || upddpl.size()>0;
		}

		public void adddpl(FileNode fn){
			bool on=upddpl.size()==0;
			upddpl.insert(fn,true);
			if(on) GLib.Idle.add(update);
		}
		public void addfile(FileNode fn){
			bool on=updfile.size()==0;
			updfile.insert(fn,true);
			if(on) GLib.Idle.add(update);
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
			ft.set(it,2,fi.get_basename());
			ch=new GLib.HashTable<string,FileNode>(null,null);
			upddpl();
		}
		~FileNode(){
			if(pa!=null) pa.updssi(-si);
			ft.remove(it);
		}
		private void updssi(int64 chg){
			ssi+=chg;
			foreach(var fc in ch.get_values()) ft.adddpl(fc);
			if(pa!=null) pa.updssi(chg);
			else ft.adddpl(this);
		}
		public void upddpl(){ ft.set(it,0,rndsi(ssi),1,pa!=null?(pa.ssi==0?0:ssi*100/pa.ssi):100,3,ssi); }
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
		private string rndtime(TimeVal time){ return time.to_iso8601(); }
		private string rndmode(uint mode){ return "%c%c%c%c%c%c%c%c%c".printf('r','w','x','r','w','x','r','w','x'); }
		public void updfile(){
			int64 nsi=0;
			try{
				GLib.FileQueryInfoFlags flags = pa==null ? GLib.FileQueryInfoFlags.NONE : GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS;
				FileInfo i=fi.query_info(FILE_ATTRIBUTE_STANDARD_ALLOCATED_SIZE+","+FILE_ATTRIBUTE_OWNER_USER+","+FILE_ATTRIBUTE_OWNER_GROUP+","+FILE_ATTRIBUTE_TIME_MODIFIED+","+FILE_ATTRIBUTE_UNIX_MODE+","+FILE_ATTRIBUTE_STANDARD_SIZE,flags,null);
				nsi=(int64)i.get_attribute_uint64(FILE_ATTRIBUTE_STANDARD_ALLOCATED_SIZE);
				TimeVal mtime;
				i.get_modification_time(out mtime);
				ft.set(it,4,rndtime(mtime));
				ft.set(it,5,rndmode(i.get_attribute_uint32(FILE_ATTRIBUTE_UNIX_MODE)));
				ft.set(it,6,i.get_attribute_string(FILE_ATTRIBUTE_OWNER_USER));
				ft.set(it,7,i.get_attribute_string(FILE_ATTRIBUTE_OWNER_GROUP));
				ft.set(it,8,rndsi(i.get_size()));
				if(fi.query_file_type(flags,null)==GLib.FileType.DIRECTORY){
					var en=fi.enumerate_children (FILE_ATTRIBUTE_STANDARD_NAME,flags);
					FileInfo fich;
					GLib.HashTable<string,FileNode> nch=new GLib.HashTable<string,FileNode>(str_hash,str_equal);
					while((fich=en.next_file())!=null){
						FileNode fn;
						if(!ch.lookup_extended(fich.get_name(),null,out fn))
							ft.addfile(fn=new FileNode(fi.get_path()+"/"+fich.get_name(),ft,this));
						nch.insert(fich.get_name(),fn);
					}
					ch=nch;
				}
				var fm=fi.monitor(FileMonitorFlags.NONE); /* TODO: monitor_directory */
				fm.changed.connect((file,otherfile,evtype)=>{
					ft.addfile(this);
				});
			}catch(Error e){
				nsi=0;
			}
			updssi(nsi-si);
			si=nsi;
		}
	}
}
