;;
;; rlyeh@reillyhayes.com
;;
;; Aurora: "A utility:  remote operations,  remote access"
;;          Really though, I named it after my dog Aurora 
;;          (who we call "Ro" for short).
;;
;; 
(provide 'aurora)

(require 'server)
(require 'dns)

(defun != (a b)
  "t if not (= a b). Compact test for call-process failure with 0"
  (not (= a b)))

(setq server-use-tcp 't)
(setq server-host "127.0.0.1")
(setq server-auth-dir "~/.emacs.d/server/")

(defvar ro-active-tunnel-list 'nil
  "List of active tunnel processes")

(defvar ro-pending-tunnel-list 'nil
  "List of tunnels waiting for connectivity")

(defcustom ro-ping-program
  (cond  ((eq system-type 'darwin)  "/sbin/ping")
          ((eq system-type 'gnu/linux) "/bin/ping"))
  "Path to the ping command"
  :type 'file
  :group 'aurora)

(defun token-n (n aregex astring &optional startpos)
  (when (string-match aregex astring (if startpos startpos 0))
    (cond ((= n 1) 
           (match-string 0 astring))
          ((> n 1)
           (token-n (- n 1) aregex astring (match-end 0))))))

(defcustom ro-server-hostname
  (cond ((eq system-type 'darwin) 
         (cond ((token-n 
                 1 "[^[:space:]\n]+" 
                 (shell-command-to-string "scutil --get LocalHostName")))
               ((getenv "SHORTHOST"))
               (t system-name)))
        ((eq system-type 'linux)
         (cond ((getenv "SHORTHOST"))
               (t system-name)))
        (t system-name))
  "A *stable* unique name for this emacs server node.  Beware of DHCP assigned names,\
 which are not as stable as you might like.  NAT can be problematic as well.\
 The name doesn't have to be resolvable, since we don't look it up."
  :type 'string
  :group 'aurora)
           
 
(defcustom ro-ping-reachablep-args
  (cond  ((eq system-type 'darwin)  "-n -q -o -t 3")
          ;; -n (no dns) -q (quiet) -o (return on 1st reply) 
          ;; -t secs (command timeout)
          ((eq system-type 'gnu/linux) "-n -q -w 3 -c 1"))
          ;; -n (no dns) -q (quiet) -w secs (command timeout)
          ;; -c n (return after n replies)
  "Args to ping for quick return with 0=reachable nozero=unreachable"
  :type 'string
  :group 'aurora)

(defcustom ro-ping-until-reachable-args
  (cond  ((eq system-type 'darwin)  "-n -q -o -i 5")
          ;; -n (no dns) -q (quiet) -o (return on 1st reply) 
          ;; -i secs (time between packets) 
          ((eq system-type 'gnu/linux) "-n -q -w 36000 -c 1 -i 5"))
          ;; -n (no dns) -q (quiet) -w secs (command timeout)
          ;; -c n (return after n replies) -i secs (time between packets)
  "Args to ping for repeated pings until first reply"
  :type 'string
  :group 'aurora)

(defcustom ro-default-host
  (getenv "DEFAULT_REMOTE_HOST")
  "The hostname to connect to by default.  Most likely your desktop"
  :type 'string
  :group 'aurora)

(defun ro-get-server-port ()
  "Get the port number for the running emacs server"
  (let ((proc-handle (get-process server-name)))
    (when proc-handle 
	(plist-get (process-contact proc-handle t) :service))))

(defvar ro-last-server-port (ro-get-server-port)
  "Last known port number for emacs server")

(defvar ro-host-ip nil
  "Ip address of host tunneled to. Local to tunnel process buffer" )

(defun ro-log (format-string &rest args)
  "Send formatted text to *aurora* buffer and as user messages"
  (let ((mod-format-string (concat format-string "\n")))
    (princ (apply 'format mod-format-string args) (get-buffer "*aurora*"))
    (apply 'message format-string args)))

(defun ro-error (&rest args)
  (apply 'ro-log args)
  nil)

(defun ro-warning (&rest args)
  (apply 'ro-log args)
  t)

(defun ro-info (&rest args)
  (apply 'ro-log args)
  t)

(defun ro-check-server ()
  "Check that the emacs server process is running and correctly configured"
  (interactive)
  ;; This is all predicated on ssh forwarding to server on loopback
  (and (server-running-p)
       (eq server-use-tcp 't)
       (string= server-host "127.0.0.1")))

(defun ro-stop-tunnel (hostname)
  "Stop tunnel"
  (interactive)
  (kill-process (ro-proc-name hostname)))

(defun ro-stop-default-tunnel ()
  "stop tunnel to default host"
  (interactive)
  (when (stringp ro-default-host)
    (ro-stop-tunnel ro-default-host)))
  
(defun ro-ssh-forward-spec (port-number)
  "Return a forward specification for the provided port-number"
  (let ((port-string (number-to-string port-number)))
    (concat port-string ":127.0.0.1:" port-string)))

(defun ro-active-p (hostname)
  "Is there an active tunnel between us and hostname?"
  (let ((proc (get-process (ro-proc-name hostname))))
    (when proc
      (and (string= (process-status proc) "run")
	   (eq (process-get proc :service) 
	       (ro-get-server-port))))))

;; (defun ro-fix-tunnel (hostname)
;;   (if (not (ro-server-active-p))
;;       (ro-server-start))
;;   (let ((proc (get-process (ro-procname hostname))))
;;     (if (not proc)
;; 	(ro-create hostname)
;;       (if (not (eq (process-get proc :service) (ro-get-server-port)))
;; 	  (ro-restart-tunnel hostname)
;; 	(ro-log (concat "Tunnel from " hostname " not broken."))))))

(defun ro-start-tunnel (hostname)
  "Start tunnel to $hostname"
  (interactive "MTo Hostname:")
  (let ((proc (get-process (ro-proc-name hostname)))
        (port (ro-get-server-port)))
    (when proc (delete-process proc))
    (let ((newproc (ro-create hostname port)))
      (when newproc
          (cond  ((ro-share-credentials hostname)
                  (add-to-list 'ro-active-tunnel-list newproc))
                 (t
                  (ro-error "Could not share server credentials")
                  (delete-process newproc)))))))

(defun ro-start-default-tunnel ()
  "Start tunnel to default host"
  (interactive)
  (when (stringp ro-default-host)
    (ro-start-tunnel ro-default-host)))

(defun ro-server-active-p ()
  "Test that the server process is still healthy"
  (string= (process-status server-name) "listen"))

(defun ro-create (hostname port)
  "Create an ssh tunnel to $hostname that forwards remote $port to local $port"
  (let* ((proc-name (ro-proc-name hostname))
	 (forward-spec (ro-ssh-forward-spec port))
	 (proc (let ((process-connection-type nil))
		 (start-process 
		  proc-name proc-name "/usr/bin/ssh" "-R" 
		  forward-spec "-o" "ExitOnForwardFailure=yes"
		  "-o" "TcpKeepAlive=yes" hostname "aurora-catch-tunnel.sh" 
                  ro-server-hostname system-name (format "%d" port)))))
                  ;;ro-delete-script credfile
    (cond (proc 
           (ro-set-host-ip hostname)
           (set-process-query-on-exit-flag proc nil)
           (process-put proc :service port)
           (process-put proc :host hostname)
           (process-put proc :ipaddr (ro-get-host-ip hostname))
           (set-process-sentinel proc 'ro-tunnel-sentinel)
           proc)
          (t
           (ro-error  "Failed to create tunnel %s to %s" 
                          proc-name forward-spec)
           nil))))

(defun ro-stop-tunnels ()
  (dolist (proc (append ro-active-tunnel-list 
                        ro-pending-tunnel-list))
    (set-process-sentinel proc 'nil)
    (delete-process proc)))

(defun ro-safe-file (file)
  "Close any unmodified buffer for file. Return unsafe for modified buffer."
  (let ((buffer (get-file-buffer (file-truename file))))
    (cond ((not buffer)
           (format "safe:%s" file))
          ((not (buffer-modified-p buffer))
           ;(kill-buffer buffer)
           (format "safe:%s" file))
          (t 
           (format "unsafe:%s" file))))) 

(defun ro-safe-file-list (file-list)
  (format "%S" (map 'list 'ro-safe-file file-list)))

(defun ro-get-host-ip (hostname)
  "Read the buffer-local variable for the host ip from the process buffer "
  (with-current-buffer (ro-proc-name hostname)
    ro-host-ip))

(defun ro-set-host-ip (hostname)
  "Query DNS for the address of hostname and set the process buffer local variable"
  (with-current-buffer (ro-proc-name hostname)
    (make-local-variable 'ro-host-ip)
    (setq ro-host-ip (dns-query hostname))))

(defun ro-proc-name (hostname)
  "Construct a unique proc-name based on the hostname"
  (format "*ro-%s*" hostname))

(defun ro-tunnel-sentinel (proc event)
  "Sentinel fn (arg to set-process-sentinel) for events on tunnel proc"
  (let ((hostname (process-get proc :host))
	(procstat (process-status proc)))
    (cond ((string= "exit" (process-status proc))
           (setq ro-active-tunnel-list (remq proc ro-active-tunnel-list))
           (ro-wait-for-host hostname)
           (ro-error "Tunnel %s aborted. Saw %s with status %s."
                           hostname event procstat))
          (t
           (ro-warning "Event on tunnel %s. Saw %s with status %s." 
		  hostname event procstat)))))

(defun ro-wait-for-host (hostname)
  "Wait for $hostname to be reachable. Triggers ro-host-sentinel"
  (let ((proc-name (format "*wait-%s*" hostname))
        (ipaddress (ro-get-host-ip hostname)))
    (when (get-process proc-name)
      (delete-process proc-name))
    (let ((proc 
	   (apply 'start-process proc-name "*aurora*" ro-ping-program
		  (append (split-string ro-ping-until-reachable-args)
                          (list ipaddress)))))
      (process-put proc :host hostname)
      (add-to-list 'ro-pending-tunnel-list proc)

      (set-process-sentinel proc 'ro-host-sentinel))))

(defun ro-host-sentinel (proc event)
  "Called when host becomes reachable again.  Restarts the tunnel to host"
  (when (string= (process-status proc) "exit")
    (let ((hostname (process-get proc :host)))
      (setq ro-pending-tunnel-list (remq proc ro-pending-tunnel-list))
      (ro-start-tunnel hostname)
      (ro-log "Restarting tunnel to %s." hostname))))
    

(defun ro-host-reachable-p (hostname)
  "Test reachability of host with ping.  Return quickly"
  (cond ((eq 0 (apply 'call-process ro-ping-program nil "*ping*" nil
                   (append (split-string ro-ping-reachablep-args)
                           (list hostname)))))
        (t 
         (ro-log "Not able to ping %s" hostname)
         nil)))

(defun ro-share-credentials (hostname)
  (if (not (ro-host-reachable-p hostname))
      (ro-error "No route to host %s" hostname)
    (let*
        ((src-file (file-truename (concat (file-name-as-directory server-auth-dir)
                                          server-name)))
         (dst-file (concat
                    "@" hostname ":"
                    (file-name-as-directory server-auth-dir)
                    ro-server-hostname))
         (dst-remote-name (concat
                           (file-name-as-directory server-auth-dir)
                           ro-server-hostname)))
      (cond ((not (file-readable-p src-file))
             (ro-error"File %s is not readable" src-file))
            ((!= 0 (call-process "scp" nil "*Messages*" nil src-file dst-file))
             (ro-error "Failed copying from %s to %s" src-file dst-file))
            (t
             (ro-info "Copied %s to %s" src-file dst-file))))))
