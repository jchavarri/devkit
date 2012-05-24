
open OUnit
open Printf
open ExtLib

open Prelude

let test_search p s =
  let module WP = Web.Provider in
  let pr = print_endline in
(*   let url = sprintf "http://www.bing.com/search?q=%s&setmkt=fr-FR&go=&qs=n&sk=&sc=8-4&form=QBRE&filt=all" (Web.urlencode s) in *)
  let html = match s with
  | `Query s ->
      let url = p.WP.request s in
      printfn "url: %s" url;
(*       let (n,res,ads) = WP.bing_html (Std.input_file "search.html") in *)
      Web.http_get url
  | `File s ->
      Std.input_file s
  in
  let (n,res,ads) = p.WP.extract_full html in
  let summary = sprintf "results %d of %d and %d ads" (Array.length res) n (Array.length ads) in
  let show = Array.iter (fun (l,_,t,d) -> pr l; pr t; pr d; pr "") in
  pr summary;
  pr "RESULTS :";
  pr "";
  show res;
(*   pr summary; *)
  pr "ADS :";
  pr "";
  show ads;
  pr summary

let test_htmlstream () =
  Printexc.record_backtrace true;
  let module HS = HtmlStream in
  let (==>) s s' = 
  try
    let s'' = Control.wrapped_output (IO.output_string ()) (fun io -> ExtStream.iter (IO.nwrite io $ HS.show_raw') (HS.parse (ExtStream.of_string s))) in
    if s' = s'' then () else
      failwith (sprintf "%s ==> %s (got %s)" s s' s'')
  with 
  | Failure s -> assert_failure s
  | exn -> assert_failure (sprintf "%s ==> %s (exn %s)\n%s" s s' (Exn.str exn) (Printexc.get_backtrace ())) 
  in
  "<q>dsds<qq>" ==> "<q>dsds<qq>";
  "<>" ==> "<>";
  "< q>" ==> "<>";
  "<q>" ==> "<q>";
  "<q><b>dsad</b></Q><Br/><a a a>" ==> "<q><b>dsad</b></q><br><a a='' a=''>";
  "<q x= a=2><q x a=2><q a=2/><q AAaa=2 />" ==> "<q x='a'><q x='' a='2'><q a='2'><q aaaa='2'>";
  "dAs<b a=\"d'dd\" b='q&q\"qq'></q a=2></><a'a>" ==> "dAs<b a='d'dd' b='q&q\"qq'></q></><a>";
  "dsad<v" ==> "dsad<v>";
  "dsa" ==> "dsa";
  "" ==> "";
  "<" ==> "<>";
  "<a q=>" ==> "<a q=''>";
  "<a q='>" ==> "<a q='>'>";
  "<a b='&amp;'>&amp;</a>" ==> "<a b='&amp;'>&amp;</a>";
  "<a b='&'>&</a>" ==> "<a b='&'>&</a>";
  ()

let test_iequal () =
  let t = let n = ref 0 in fun x -> assert_bool (sprintf "testcase %d" !n) x; incr n in
  let fail = t $ not in
  t (Stre.iequal "dSaDAS" "dsadas");
  t (Stre.iequal "dsadas" "dsadas");
  t (Stre.iequal "../@423~|" "../@423~|");
  t (Stre.iequal "" "");
  t (Stre.iequal "привет" "привет");
  t (Stre.iequal "hello" "HELLO");
  fail (Stre.iequal "hello" "hello!");
  fail (Stre.iequal "hello1" "hello!");
  ()

let test_iexists () =
  let f = Stre.iexists in
  let t = let n = ref 0 in fun x -> assert_bool (sprintf "testcase %d" !n) x; incr n in
  let fail = t $ not in
  t (f "xxxxdSaDAS" "dsadas");
  t (f "dSaDASxxxx" "dsadas");
  t (f "dSaDAS" "dsadas");
  t (f "xxxxdSaDASxxxx" "dsadas");
  t (f "xxxxdSaDAS" "DsAdAs");
  t (f "dSaDAS" "DsAdAs");
  t (f "xxxxdSaDASxxxx" "DsAdAs");
  t (f "dSaDASxxxx" "DsAdAs");
  t (f "xxxxdSaDAS" "");
  t (f "" "");
  t (f "12;dsaпривет" "привет");
  t (f "12;dsaпривет__324" "привет");
  fail (f "" "DsAdAs");
  fail (f "hello" "hellu");
  fail (f "hello" "hello!");
  fail (f "xxxxhello" "hello!");
  fail (f "helloxxx" "hello!");
  fail (f "hellox!helloXxx" "hello!");
  fail (f "" "x");
  fail (f "xyXZZx!x_" "xx");
  ()

let test_lim_cache () =
  let module T = Cache.SizeLimited in
  let c = T.create 100 in
  let key = T.key in
  let test_get k = assert_equal ~printer:Std.dump (T.get c k) in
  let some k v = test_get (key k) (Some v) in
  let none k = test_get (key k) None in
  let iter f i1 i2 = for x = i1 to i2 do f x done in
  iter (fun i ->
    iter none i (1000+i);
    assert_equal (key i) (T.add c i);
    some i i) 0 99;
  iter (fun i ->
    iter none i (1000+i);
    iter (fun k -> some k k) (i-100) (i-1);
    assert_equal (key i) (T.add c i);
    some i i) 100 999;
  iter none 0 899;
  iter (fun k -> some k k) 900 999;
  iter none 1000 2000;
  ()

let test_split_by_words () =
  let t = let n = ref 0 in fun x -> assert_bool (sprintf "testcase %d" !n) x; incr n in
  let f a l = t (Stre.split Stre.by_words a = l) in
  f ("a" ^ String.make 10 '_' ^ "b") ["a"; "b"];
  f ("a" ^ String.make 1024 ' ' ^ "b") ["a"; "b"];
  f ("a" ^ String.make 10240 ' ' ^ "b") ["a"; "b"];
  ()

let test_threadpool () =
  let module TP = Parallel.ThreadPool in
  let pool = TP.create 3 in
  TP.wait_blocked pool;
  let i = ref 0 in
  for j = 1 to 10 do
    let worker _k () = incr i; Nix.sleep 0.2 in
    TP.put pool (worker j);
  done;
  TP.wait_blocked pool;
  assert_equal !i 10;
  ()

let tests () = 
  run_test_tt ("devkit" >::: [
    "HtmlStream" >:: test_htmlstream;
    "Stre.ieuqual" >:: test_iequal;
    "Stre.iexists" >:: test_iexists;
    "Cache.SizeLimited" >:: test_lim_cache;
    "split by words" >:: test_split_by_words;
    "ThreadPool test" >:: test_threadpool;
  ]) >> ignore

let () =
  match Array.to_list Sys.argv with
  | [_;src;"query";query] -> test_search (Web.Provider.by_name src) (`Query query)
  | [_;src;"file";file] -> test_search (Web.Provider.by_name src) (`File file)
  | _ -> tests ()

