(** 
  Global ready-to-use logger 

  TODO interface to manage State
*)

(**
{2 Example usage}

Create logging facility (messages origin)
{[let http = Log.facility "http"]}

Log from http subsystem at debug level
{[Log.debug http "received %u bytes"]}

Create and use object for http logging
{[let log = Log.from "http" (* new Log.logger http *);;
log#info "sent %u bytes" 1024
log#warn ~exn "failed here"
]}

Output only messages of warning level or higher for the http facility
{[http#allow `Warn]}
or
{[Logger.set_filter http `Warn]}
or
{[Log.set_filter ~name:"http" `Warn]}

Output only messages of warning level or higher for all facilities
{[Log.set_filter `Warn]}

{2 API}
*)

open Printf
open ExtLib

(** Global logger state *)
module State = struct

  let all = Hashtbl.create 10
  let default_level = ref (`Info : Logger.level)

  let facility name =
    try
      Hashtbl.find all name
    with
      Not_found ->
        let x = { Logger.name = name; show = Logger.int_level !default_level } in
        Hashtbl.add all name x; 
        x

  let set_filter ?name level =
    match name with
    | None -> default_level := level; Hashtbl.iter (fun _ x -> Logger.set_filter x level) all
    | Some name -> Logger.set_filter (facility name) level

  let output_ch ch = 
    fun str -> try output_string ch str; flush ch with _ -> () (* logging never fails, most probably ENOSPC *)

  let format_simple level facil msg =
    sprintf "[%s] %06u:%04u [%s:%s] %s\n" 
      (Time.to_string ~gmt:false ~ms:true (Unix.gettimeofday ())) 
      (Unix.getpid ()) 
      (Thread.id (Thread.self ()))
      facil.Logger.name
      (Logger.string_level level)
      msg

  let log_ch = ref stderr
  let output = ref (output_ch stderr)
  let base_name = ref ""
  let need_rotation = ref (fun _ -> false)

  module Put = Logger.PutSimple(
  struct
    let format = format_simple
    let output = fun s -> !output s
  end)

  module M = Logger.Make(Put)

  let self = "lib"

  let reopen_log_ch ?(self_call=false) file =
    try
      if self_call = false then base_name := file;
      let ch = Files.open_out_append_text file in
      output := output_ch ch;
      Unix.dup2 (Unix.descr_of_out_channel ch) Unix.stderr;
(*       if !log_ch <> stderr then close_out_noerr !log_ch; *)
      log_ch := ch
    with
      e -> M.warn (facility self) "reopen_log_ch(%s) failed : %s" file (Printexc.to_string e)

  let find_possible_rotation () =
    let i = ref 0 in
    while Sys.file_exists (sprintf "%s.%d" !base_name !i) do incr i done;
    !i

  let rollback () =
    for i = 2 to 10 do
      try Unix.rename (sprintf "%s.%d" !base_name i) (sprintf "%s.%d" !base_name (i - 1)) with _ -> ()
    done;
    ()

  let do_rotation () =
    if !base_name <> "" then
    begin
      let i = find_possible_rotation () in
      if i > 10 then rollback ();
      let i = min i 10 in
      Sys.rename !base_name (sprintf "%s.%d" !base_name i);
      reopen_log_ch ~self_call:true !base_name
    end

  let check_rotation () =
    if !base_name <> "" then
    begin
      let stats = Unix.fstat (Unix.descr_of_out_channel !log_ch) in
      (!need_rotation stats) && (stats.Unix.st_kind = Unix.S_REG)
    end else false (* no rotation with empty basename*)

  let rotation_i = ref 0

  let rotate () = incr rotation_i; if !rotation_i > 1_000 then begin rotation_i:=0; if check_rotation () then do_rotation () end

  let set_rotation f = need_rotation := f

end

include State.M

let facility = State.facility
let set_filter = State.set_filter

type 'a pr = ?exn:exn -> ('a, unit, string, unit) format4 -> 'a

class logger facil =
let perform f =
  fun ?exn fmt ->
    try State.rotate ();
    match exn with
    | Some exn -> ksprintf (fun s -> f facil (s ^ " : exn " ^ Exn.str exn)) fmt
    | None -> ksprintf (f facil) fmt
    with exn -> ksprintf (fun s -> f facil (sprintf "Failed : %s with message %s" (Exn.str exn) s)) fmt
in
object
method debug : 'a. 'a pr = perform debug_s
method warn : 'a. 'a pr = perform warn_s
method info : 'a. 'a pr = perform info_s
method error : 'a. 'a pr = perform error_s
method allow (level:Logger.level) = Logger.set_filter facil level
method level : Logger.level = Logger.get_level facil
method name = facil.Logger.name
end

let from name = new logger (facility name)

(** internal logging facility *)
let self = from State.self

(** general logging facility *)
let main = from "main"

(** reopen log file *)
let reopen = function
| None -> ()
| Some name -> State.reopen_log_ch name

(** set log rotation **)
type rotation =
| No_rotation
| Days_rotation of int
| Size_rotation of int
| OnceAday_rotation

let log_start = ref (Time.now())
let cur_size = ref 0

let set_rotation = function
| No_rotation -> ()
| Days_rotation d -> State.set_rotation (fun _ -> let cur_time = Time.now() in if cur_time -. !log_start > (float d) *. 60. *. 60. then (log_start := Time.now();true) else false)
| Size_rotation s -> State.set_rotation (fun stats -> stats.Unix.st_size > s * 1024 * 1024)
| OnceAday_rotation -> State.set_rotation (fun _ -> let get_day s = (Unix.gmtime s).Unix.tm_yday in if get_day (Time.now()) <> get_day (!log_start) then (log_start := Time.now(); true) else false)
