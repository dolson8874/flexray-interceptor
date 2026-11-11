using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Runtime.InteropServices;

// Local, read-only Cap'n Proto inspection of unpacked cereal Event streams.
// Field names come from the route's public log.capnp reference; no uploads.
public static class RouteReview {
  [StructLayout(LayoutKind.Sequential)] struct ZBuffer { public IntPtr data; public UIntPtr size, pos; }
  const string Zstd = @"C:\Program Files\Git\mingw64\bin\libzstd.dll";
  [DllImport(Zstd)] static extern IntPtr ZSTD_createDStream();
  [DllImport(Zstd)] static extern UIntPtr ZSTD_initDStream(IntPtr stream);
  [DllImport(Zstd)] static extern UIntPtr ZSTD_decompressStream(IntPtr stream, ref ZBuffer output, ref ZBuffer input);
  [DllImport(Zstd)] static extern uint ZSTD_isError(UIntPtr code);
  [DllImport(Zstd)] static extern IntPtr ZSTD_getErrorName(UIntPtr code);
  [DllImport(Zstd)] static extern UIntPtr ZSTD_freeDStream(IntPtr stream);
  static void Check(UIntPtr code) { if (ZSTD_isError(code)!=0) throw new Exception(Marshal.PtrToStringAnsi(ZSTD_getErrorName(code))); }
  static byte[] Decompress(string path) {
    byte[] src=File.ReadAllBytes(path), dst=new byte[1024*1024];
    GCHandle s=GCHandle.Alloc(src,GCHandleType.Pinned), d=GCHandle.Alloc(dst,GCHandleType.Pinned);
    IntPtr stream=ZSTD_createDStream();
    try {
      Check(ZSTD_initDStream(stream));
      ZBuffer input=new ZBuffer { data=s.AddrOfPinnedObject(),size=(UIntPtr)(uint)src.Length,pos=UIntPtr.Zero };
      using (MemoryStream result=new MemoryStream()) {
        UIntPtr remaining=UIntPtr.Zero;
        while (input.pos.ToUInt64()<input.size.ToUInt64()) {
          ZBuffer output=new ZBuffer {data=d.AddrOfPinnedObject(),size=(UIntPtr)(uint)dst.Length,pos=UIntPtr.Zero};
          ulong before=input.pos.ToUInt64();
          remaining=ZSTD_decompressStream(stream,ref output,ref input);Check(remaining);
          int n=(int)output.pos.ToUInt64();result.Write(dst,0,n);
          if (n==0 && before==input.pos.ToUInt64()) throw new Exception("Zstd made no progress");
        }
        if (remaining!=UIntPtr.Zero) throw new Exception("Truncated Zstd frame: "+path);
        return result.ToArray();
      }
    } finally { ZSTD_freeDStream(stream);s.Free();d.Free(); }
  }
  sealed class Obj { public int seg, at, dw, pw, count, elem; public bool nil; }
  sealed class Message {
    public byte[] bytes;public int[] starts, sizes;public int end;
    public Message(byte[] b,int offset) {
      bytes=b;int n=checked((int)BitConverter.ToUInt32(b,offset)+1);
      if(n<1||n>512)throw new Exception("Invalid segment count at "+offset);
      starts=new int[n];sizes=new int[n];int header=(4+4*n+7)&~7;int pos=offset+header;
      for(int i=0;i<n;i++){int words=checked((int)BitConverter.ToUInt32(b,offset+4+4*i));starts[i]=pos;sizes[i]=checked(words*8);pos=checked(pos+sizes[i]);}
      if(pos>b.Length)throw new Exception("Truncated Cap'n Proto message");end=pos;
    }
    public ulong Word(int seg,int at){if(seg<0||seg>=starts.Length||at<0||at+8>sizes[seg])throw new Exception("Pointer out of segment");return BitConverter.ToUInt64(bytes,starts[seg]+at);}
    public Obj Ptr(int seg,int at){return Decode(seg,at,Word(seg,at),0,-1);}
    Obj Decode(int seg,int at,ulong w,int depth,int target) {
      if(depth>16)throw new Exception("Far-pointer cycle");
      if(w==0)return new Obj{nil=true};
      int kind=(int)(w&3);
      if(kind==2){int s=(int)(w>>32),landing=(int)((w>>3)&0x1fffffff)*8;
        if((w&4)==0)return Decode(s,landing,Word(s,landing),depth+1,-1);
        ulong far=Word(s,landing),tag=Word(s,landing+8);
        if((far&7)!=2)throw new Exception("Invalid double-far landing pad");
        return Decode((int)(far>>32),0,tag,depth+1,(int)((far>>3)&0x1fffffff)*8);
      }
      int relative=((int)(uint)w)>>2;int dest=target>=0?target:checked(at+8+relative*8);
      if(kind==0)return new Obj{seg=seg,at=dest,dw=(int)((w>>32)&65535),pw=(int)(w>>48)};
      if(kind==1){int elem=(int)((w>>32)&7),count=(int)(w>>35);
        if(elem==7){ulong tag=Word(seg,dest);if((tag&3)!=0)throw new Exception("Invalid composite list");
          return new Obj{seg=seg,at=dest+8,dw=(int)((tag>>32)&65535),pw=(int)(tag>>48),count=(int)((tag>>2)&0x3fffffff),elem=7};}
        return new Obj{seg=seg,at=dest,count=count,elem=elem};}
      throw new Exception("Unsupported pointer kind");
    }
    public Obj Field(Obj o,int p){return p<o.pw?Ptr(o.seg,o.at+o.dw*8+p*8):new Obj{nil=true};}
    public Obj Item(Obj o,int i){if(o.elem!=7||i>=o.count)throw new Exception("Expected composite list");return new Obj{seg=o.seg,at=o.at+i*(o.dw+o.pw)*8,dw=o.dw,pw=o.pw};}
    public byte[] Data(Obj o){if(o.nil)return new byte[0];if(o.elem!=2)throw new Exception("Expected byte list");if(o.at<0||o.at+o.count>sizes[o.seg])throw new Exception("Byte list out of bounds");byte[] r=new byte[o.count];Buffer.BlockCopy(bytes,starts[o.seg]+o.at,r,0,r.Length);return r;}
    public string Text(Obj o){return Encoding.UTF8.GetString(Data(o)).TrimEnd('\0');}
    public uint U32(Obj o,int offset){if(offset+4>o.dw*8)return 0;return BitConverter.ToUInt32(bytes,starts[o.seg]+o.at+offset);}
    public byte U8(Obj o,int offset){return offset<o.dw*8?bytes[starts[o.seg]+o.at+offset]:(byte)0;}
  }
  sealed class Count {public long count,bytes;public int min=Int32.MaxValue,max;public double first,last;}
  static string Csv(string v){return "\""+v.Replace("\"","\"\"")+"\"";}
  public static void Analyze(string route,string output,string schema) {
    Directory.CreateDirectory(output);
    string eventSchema=File.ReadAllText(schema).Split(new[]{"struct Event {"},StringSplitOptions.None)[1];
    var fields=Regex.Matches(eventSchema,@"(?m)^\s*(\w+)\s+@(\d+)\s*:").Cast<Match>().Select(m=>new {name=m.Groups[1].Value,ord=int.Parse(m.Groups[2].Value)}).Where(x=>x.ord!=0&&x.ord!=67).OrderBy(x=>x.ord).ToArray();
    var events=new SortedDictionary<string,long>();var packets=new SortedDictionary<string,Count>();
    using(var diag=new StreamWriter(Path.Combine(output,"diagnostics.csv")))
    using(var logs=new StreamWriter(Path.Combine(output,"messages.jsonl")))
    using(var managers=new StreamWriter(Path.Combine(output,"flexray_process.csv")))
    using(var oslogs=new StreamWriter(Path.Combine(output,"os_messages.jsonl")))
    using(var init=new StreamWriter(Path.Combine(output,"init_metadata.txt")))
    using(var segments=new StreamWriter(Path.Combine(output,"segments.csv"))){
      diag.WriteLine("segment,time_s,source,address_hex,length,data_hex");managers.WriteLine("segment,time_s,name,pid,running,should_run,exit_code");segments.WriteLine("segment,events,can_events,can_frames,flexray_frames,diagnostic_frames,first_s,last_s,uncompressed_bytes");
      foreach(string dir in Directory.GetDirectories(route).OrderBy(p=>int.Parse(p.Substring(p.LastIndexOf("--")+2)))){
        string path=Path.Combine(dir,"rlog.zst");if(!File.Exists(path))continue;
        string segment=Path.GetFileName(dir);byte[] b=Decompress(path);int pos=0;long total=0,canEvents=0,frames=0,fr=0,diagnostic=0;double first=0,last=0;
        while(pos<b.Length){Message m=new Message(b,pos);pos=m.end;Obj root=m.Ptr(0,0);if(root.nil||root.dw<2)throw new Exception("Invalid Event root");
          double t=BitConverter.ToUInt64(b,m.starts[root.seg]+root.at)/1e9;if(total==0)first=t;last=t;total++;
          ushort discr=(ushort)(m.U32(root,8)&65535);string name=discr<fields.Length?fields[discr].name:"unknown_"+discr;
          if(!events.ContainsKey(name))events[name]=0;events[name]++;
          Obj body=m.Field(root,0);
          if(name=="can"||name=="sendcan"){
            if(name=="can")canEvents++;
            if(body.nil)continue;if(body.elem!=7)throw new Exception("CAN is not composite list");
            for(int i=0;i<body.count;i++){Obj f=m.Item(body,i);uint address=m.U32(f,0);int src=m.U8(f,6);byte[] data=m.Data(m.Field(f,0));
              string key=name+","+src+","+address.ToString("X");Count c;if(!packets.TryGetValue(key,out c)){c=new Count{first=t};packets[key]=c;}c.count++;c.bytes+=data.Length;c.min=Math.Min(c.min,data.Length);c.max=Math.Max(c.max,data.Length);c.last=t;
              if(name!="can")continue;frames++;if(src==4||src==6)fr++;
              if(address==0x1fa){diagnostic++;diag.WriteLine(segment+","+t.ToString("F9",System.Globalization.CultureInfo.InvariantCulture)+","+src+",1FA,"+data.Length+","+BitConverter.ToString(data).Replace("-",""));}
            }
          }else if(name=="logMessage"||name=="errorLogMessage"){
            string text=m.Text(body);logs.WriteLine("{\"segment\":"+Json(segment)+",\"time_s\":"+t.ToString("F9",System.Globalization.CultureInfo.InvariantCulture)+",\"type\":"+Json(name)+",\"text\":"+Json(text)+"}");
          }else if(name=="managerState"){
            Obj list=m.Field(body,0);if(!list.nil){for(int i=0;i<list.count;i++){Obj process=m.Item(list,i);string pname=m.Text(m.Field(process,0));if(pname.IndexOf("flex",StringComparison.OrdinalIgnoreCase)>=0)managers.WriteLine(segment+","+t.ToString("F9",System.Globalization.CultureInfo.InvariantCulture)+","+Csv(pname)+","+(int)m.U32(process,0)+","+((m.U8(process,4)&1)!=0)+","+((m.U8(process,4)&2)!=0)+","+(int)m.U32(process,8));}}
          }else if(name=="operatingSystemLog"){
            oslogs.WriteLine("{\"segment\":"+Json(segment)+",\"time_s\":"+t.ToString("F9",System.Globalization.CultureInfo.InvariantCulture)+",\"tag\":"+Json(m.Text(m.Field(body,0)))+",\"message\":"+Json(m.Text(m.Field(body,1)))+"}");
          }else if(name=="initData"){
            init.WriteLine("SEGMENT "+segment+" time="+t+" device_type="+(m.U32(body,0)&65535));
            int[] indexes={3,8,9,10,12,15,17,19,20};string[] labels={"version","gitCommit","gitBranch","gitRemote","kernelVersion","osVersion","gitCommitDate","gitSrcCommit","gitSrcCommitDate"};
            for(int i=0;i<indexes.Length;i++)init.WriteLine(labels[i]+"="+m.Text(m.Field(body,indexes[i])));
            // InitData.params: Map(Text, Data). Save only FlexRay parameter values.
            Obj map=m.Field(body,14);if(!map.nil){Obj entries=m.Field(map,0);if(!entries.nil){for(int i=0;i<entries.count;i++){Obj entry=m.Item(entries,i);string key=m.Text(m.Field(entry,0));if(key.IndexOf("flex",StringComparison.OrdinalIgnoreCase)>=0)init.WriteLine("param."+key+"="+m.Text(m.Field(entry,1)));}}}
          }
        }
        segments.WriteLine(segment+","+total+","+canEvents+","+frames+","+fr+","+diagnostic+","+first.ToString("F6",System.Globalization.CultureInfo.InvariantCulture)+","+last.ToString("F6",System.Globalization.CultureInfo.InvariantCulture)+","+b.Length);segments.Flush();diag.Flush();logs.Flush();managers.Flush();oslogs.Flush();init.Flush();
        Console.WriteLine(segment+" events="+total+" CAN="+frames+" FlexRay="+fr+" diag="+diagnostic);
      }
    }
    using(var writer=new StreamWriter(Path.Combine(output,"event_counts.csv"))){writer.WriteLine("type,count");foreach(var item in events)writer.WriteLine(item.Key+","+item.Value);}
    using(var writer=new StreamWriter(Path.Combine(output,"packet_counts.csv"))){writer.WriteLine("type,source,address_hex,count,bytes,min_len,max_len,first_s,last_s");foreach(var item in packets){Count c=item.Value;writer.WriteLine(item.Key+","+c.count+","+c.bytes+","+c.min+","+c.max+","+c.first.ToString("F6",System.Globalization.CultureInfo.InvariantCulture)+","+c.last.ToString("F6",System.Globalization.CultureInfo.InvariantCulture));}}
  }
  static string Json(string s){StringBuilder b=new StringBuilder("\"");foreach(char c in s){switch(c){case '\\':b.Append("\\\\");break;case '"':b.Append("\\\"");break;case '\n':b.Append("\\n");break;case '\r':b.Append("\\r");break;case '\t':b.Append("\\t");break;default:if(c<32)b.Append("\\u"+((int)c).ToString("x4"));else b.Append(c);break;}}return b.Append('"').ToString();}
}
