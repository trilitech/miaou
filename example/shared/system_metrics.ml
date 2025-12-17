(*****************************************************************************)
(*                                                                           *)
(* SPDX-License-Identifier: MIT                                              *)
(* Copyright (c) 2025 Nomadic Labs <contact@nomadic-labs.com>                *)
(*                                                                           *)
(*****************************************************************************)

(** System metrics reader for Linux /proc filesystem. *)

(* CPU usage tracking *)
type cpu_stats = {
  user : int;
  nice : int;
  system : int;
  idle : int;
  iowait : int;
  irq : int;
  softirq : int;
  steal : int;
}

let last_cpu_stats : cpu_stats option ref = ref None

let read_cpu_stats () =
  try
    let ic = open_in "/proc/stat" in
    let line = input_line ic in
    close_in ic ;
    (* Parse "cpu  user nice system idle iowait irq softirq steal" *)
    let parts = String.split_on_char ' ' line in
    let nums = List.filter (fun s -> s <> "" && s <> "cpu") parts in
    match nums with
    | user :: nice :: system :: idle :: iowait :: irq :: softirq :: steal :: _
      ->
        Some
          {
            user = int_of_string user;
            nice = int_of_string nice;
            system = int_of_string system;
            idle = int_of_string idle;
            iowait = int_of_string iowait;
            irq = int_of_string irq;
            softirq = int_of_string softirq;
            steal = int_of_string steal;
          }
    | _ -> None
  with _ -> None

let get_cpu_usage () =
  match read_cpu_stats () with
  | None -> 0.0
  | Some current -> (
      match !last_cpu_stats with
      | None ->
          last_cpu_stats := Some current ;
          0.0
      | Some prev ->
          last_cpu_stats := Some current ;
          let prev_idle = prev.idle + prev.iowait in
          let curr_idle = current.idle + current.iowait in
          let prev_total =
            prev.user + prev.nice + prev.system + prev_idle + prev.irq
            + prev.softirq + prev.steal
          in
          let curr_total =
            current.user + current.nice + current.system + curr_idle
            + current.irq + current.softirq + current.steal
          in
          let total_diff = curr_total - prev_total in
          let idle_diff = curr_idle - prev_idle in
          if total_diff = 0 then 0.0
          else
            let usage =
              100.0
              *. (float_of_int (total_diff - idle_diff)
                 /. float_of_int total_diff)
            in
            max 0.0 (min 100.0 usage))

(* Memory usage *)
let get_memory_usage () =
  try
    let ic = open_in "/proc/meminfo" in
    let rec read_lines mem_total mem_available =
      try
        let line = input_line ic in
        if String.length line > 9 && String.sub line 0 9 = "MemTotal:" then
          let parts = String.split_on_char ' ' line in
          let nums =
            List.filter
              (fun s -> s <> "" && s <> "MemTotal:" && s <> "kB")
              parts
          in
          let total = match nums with n :: _ -> int_of_string n | _ -> 0 in
          read_lines total mem_available
        else if
          String.length line > 13 && String.sub line 0 13 = "MemAvailable:"
        then
          let parts = String.split_on_char ' ' line in
          let nums =
            List.filter
              (fun s -> s <> "" && s <> "MemAvailable:" && s <> "kB")
              parts
          in
          let avail = match nums with n :: _ -> int_of_string n | _ -> 0 in
          read_lines mem_total avail
        else read_lines mem_total mem_available
      with End_of_file -> (mem_total, mem_available)
    in
    let mem_total, mem_available = read_lines 0 0 in
    close_in ic ;
    if mem_total = 0 then 0.0
    else
      let used = mem_total - mem_available in
      100.0 *. (float_of_int used /. float_of_int mem_total)
  with _ -> 0.0

(* Network usage - bytes per second *)
let last_net_bytes : (int * float) option ref = ref None

let get_network_usage () =
  try
    let ic = open_in "/proc/net/dev" in
    (* Skip first two header lines *)
    ignore (input_line ic) ;
    ignore (input_line ic) ;
    let rec sum_bytes total =
      try
        let line = input_line ic in
        (* Parse "  eth0: 123456 ..." - get rx_bytes (first number after colon) *)
        let parts = String.split_on_char ':' line in
        match parts with
        | _ :: rest_parts -> (
            let rest_str = String.concat ":" rest_parts in
            let nums =
              String.split_on_char ' ' (String.trim rest_str)
              |> List.filter (fun s -> s <> "")
            in
            match nums with
            | rx_bytes :: _ -> sum_bytes (total + int_of_string rx_bytes)
            | _ -> sum_bytes total)
        | _ -> sum_bytes total
      with End_of_file -> total
    in
    let total_bytes = sum_bytes 0 in
    close_in ic ;
    let now = Unix.gettimeofday () in
    match !last_net_bytes with
    | None ->
        last_net_bytes := Some (total_bytes, now) ;
        0.0
    | Some (prev_bytes, prev_time) ->
        last_net_bytes := Some (total_bytes, now) ;
        let bytes_diff = total_bytes - prev_bytes in
        let time_diff = now -. prev_time in
        if time_diff = 0.0 then 0.0
        else
          (* Return KB/s, capped at 100 for display *)
          let kbps = float_of_int bytes_diff /. time_diff /. 1024.0 in
          min 100.0 (max 0.0 kbps)
  with _ -> 0.0

(* Check if we're on Linux with /proc *)
let is_supported () =
  try
    Sys.file_exists "/proc/stat"
    && Sys.file_exists "/proc/meminfo"
    && Sys.file_exists "/proc/net/dev"
  with _ -> false

(* Get system uptime in seconds *)
let get_uptime () =
  try
    let ic = open_in "/proc/uptime" in
    let line = input_line ic in
    close_in ic ;
    let parts = String.split_on_char ' ' line in
    match parts with uptime :: _ -> float_of_string uptime | _ -> 0.0
  with _ -> 0.0

(* Get load average *)
let get_load_average () =
  try
    let ic = open_in "/proc/loadavg" in
    let line = input_line ic in
    close_in ic ;
    let parts = String.split_on_char ' ' line in
    match parts with
    | load1 :: load5 :: load15 :: _ ->
        (float_of_string load1, float_of_string load5, float_of_string load15)
    | _ -> (0.0, 0.0, 0.0)
  with _ -> (0.0, 0.0, 0.0)
