# Copyright (C) 2007-2015 X2Go Project - http://wiki.x2go.org
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the
# Free Software Foundation, Inc.,
# 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Copyright (C) 2007-2015 Oleksandr Shneyder <oleksandr.shneyder@obviously-nice.de>
# Copyright (C) 2007-2015 Heinz-Markus Graesing <heinz-m.graesing@obviously-nice.de>

package X2Go::Server::DB;

=head1 NAME

X2Go::Server::DB - X2Go Session Database package for Perl

=head1 DESCRIPTION

X2Go::Server::DB Perl package for X2Go::Server.

=cut

use strict;
use DBI;
use POSIX;
use Sys::Syslog qw( :standard :macros );

use X2Go::Config qw( get_sqlconfig );
use X2Go::Log qw( loglevel );
use X2Go::Server::DB::PostgreSQL;
use X2Go::Utils qw( system_capture_merged_output system_capture_stdout_output );
setlogmask( LOG_UPTO(loglevel()) );


my ($uname, $pass, $uid, $pgid, $quota, $comment, $gcos, $homedir, $shell, $expire) = getpwuid(getuid());

my $Config = get_sqlconfig();
my $x2go_lib_path=system_capture_stdout_output("x2gopath", "libexec");

my $backend=$Config->param("backend");

my $host;
my $port;
my $db="x2go_sessions";
my $dbpass;
my $dbuser;
my $sslmode;

if ($backend ne 'postgres' && $backend ne 'sqlite')
{
	die "unknown backend $backend";
}

use base 'Exporter';

our @EXPORT=('db_listsessions','db_listsessions_all', 'db_getservers', 'db_getagent', 'db_resume', 'db_changestatus', 'db_getstatus', 
             'db_getdisplays', 'db_insertsession', 'db_insertshadowsession', 'db_getports', 'db_insertport', 'db_rmport', 'db_createsession', 'db_createshadowsession', 'db_insertmount', 
             'db_getmounts', 'db_deletemount', 'db_getdisplay', 'dbsys_getmounts', 'dbsys_listsessionsroot', 'dbsys_listsessionsroot_all', 'dbsys_rmsessionsroot', 
	     'dbsys_listhistoryroot','dbsys_listhistoryroot_all', 'db_listhistory', 'db_listhistory_all', 'dbsys_storehistoryroot', 
	     'dbsys_deletemounts', 'db_listshadowsessions', 'db_listshadowsessions_all');

sub dbsys_rmsessionsroot
{
	my $sid=shift or die "argument \"session_id\" missed";
	dbsys_deletemounts($sid);
	if($backend eq 'postgres')
	{
		X2Go::Server::DB::PostgreSQL::dbsys_rmsessionsroot($sid);
	}
	if($backend eq 'sqlite')
	{
		system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "rmsessionsroot", "$sid");
	}

}

sub dbsys_listhistoryroot
{
	my $server=shift or die "argument \"server\" missed";
	if($backend eq 'postgres')
	{
		return X2Go::Server::DB::PostgreSQL::dbsys_listhistoryroot($server);
	}
	if($backend eq 'sqlite')
	{
		return split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "listhistoryroot", "$server"));
	}
}

sub dbsys_listhistoryroot_all
{
	if($backend eq 'postgres')
	{
		return X2Go::Server::DB::PostgreSQL::dbsys_listhistoryroot_all();
	}
	if($backend eq 'sqlite')
	{
		return split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "listhistoryroot_all"));  
	}
}

sub dbsys_storehistoryroot
{
	my $sid=shift or die "argument \"session_id\" missed";
	if($backend eq 'postgres')
	{
		X2Go::Server::DB::PostgreSQL::dbsys_storehistoryroot($sid);
	}
	if($backend eq 'sqlite')
	{
		system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "storehistoryroot", "$sid");
	}
}

sub dbsys_deletemounts
{
	my $sid=shift or die "argument \"session_id\" missed";
	if ($backend eq 'postgres')
	{
		X2Go::Server::DB::PostgreSQL::dbsys_deletemounts($sid);
	}
	if ($backend eq 'sqlite')
	{
		system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "deletemounts", "$sid");
	}
	syslog('debug', "dbsys_deletemounts called, session ID: $sid");
}

sub dbsys_listsessionsroot
{
	my $server=shift or die "argument \"server\" missed";
	if ($backend eq 'postgres')
	{
		return X2Go::Server::DB::PostgreSQL::dbsys_listsessionsroot($server);
	}
	if($backend eq 'sqlite')
	{
		return split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "listsessionsroot", "$server"));
	}
}

sub dbsys_listsessionsroot_all
{
	if ($backend eq 'postgres')
	{
		return X2Go::Server::DB::PostgreSQL::dbsys_listsessionsroot_all();
	}
	if ($backend eq 'sqlite')
	{
		return split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "listsessionsroot_all"));
	}
}

sub dbsys_getmounts
{
	my @mounts;
	my $sid=shift or die "argument \"session_id\" missed";
	if ($backend eq 'postgres')
	{
		@mounts = X2Go::Server::DB::PostgreSQL::dbsys_getmounts($sid);
	}
	if ($backend eq 'sqlite')
	{
		@mounts = split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "getmounts", "$sid"));
	}
	my $log_retval = join(" ", @mounts);
	syslog('debug', "dbsys_getmounts called, session ID: $sid; return value: $log_retval");
	return @mounts;
}

sub db_getmounts
{
	my @mounts;
	my $sid=shift or die "argument \"session_id\" missed";
	if($backend eq 'postgres')
	{
		@mounts = X2Go::Server::DB::PostgreSQL::db_getmounts($sid);
	}
	if ($backend eq 'sqlite')
	{
		@mounts = split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "getmounts", "$sid"));
	}
	my $log_retval = join(" ", @mounts);
	syslog('debug', "db_getmounts called, session ID: $sid; return value: $log_retval");
	return @mounts;
}

sub db_deletemount
{
	my $sid=shift or die "argument \"session_id\" missed";
	my $path=shift or die "argument \"path\" missed";
	if ($backend eq 'postgres')
	{
		X2Go::Server::DB::PostgreSQL::db_deletemount($sid, $path);
	}
	if ($backend eq 'sqlite')
	{
		system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "deletemount", "$sid", "$path");
	}
	syslog('debug', "db_deletemount called, session ID: $sid, path: $path");
}

sub db_insertmount
{
	my $sid=shift or die "argument \"session_id\" missed";
	my $path=shift or die "argument \"path\" missed";
	my $client=shift or die "argument \"client\" missed";
	my $res_ok=0;
	if ($backend eq 'postgres')
	{
		$res_ok = X2Go::Server::DB::PostgreSQL::db_insertmount($sid, $path, $client);
	}
	if ($backend eq 'sqlite')
	{
		if( system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "insertmount", "$sid", "$path", "$client") eq "ok")
		{
			$res_ok=1;
		}
	}
	syslog('debug', "db_insertmount called, session ID: $sid, path: $path, client: $client; return value: $res_ok");
	return $res_ok;
}

sub db_insertsession
{
	my $display=shift or die "argument \"display\" missed";
	my $server=shift or die "argument \"server\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	if ($backend eq 'postgres')
	{
		X2Go::Server::DB::PostgreSQL::db_insertsession($display, $server, $sid);
	}
	if ($backend eq 'sqlite')
	{
		my $err=system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "insertsession", "$display", "$server", "$sid");
		if ($err ne "ok")
		{
			die "$err: $x2go_lib_path/libx2go-server-db-sqlite3-wrapper insertsession $display $server $sid";
		}
	}
	syslog('debug', "db_insertsession called, session ID: $sid, server: $server, session ID: $sid");
}

sub db_insertshadowsession
{
	my $display=shift or die "argument \"display\" missed";
	my $server=shift or die "argument \"server\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	my $shadreq_user=shift or die "argument \"shadreq_user\" missed";
	if ($backend eq 'postgres')
	{
		X2Go::Server::DB::PostgreSQL::db_insertshadowsession($display, $server, $sid, $shadreq_user);
	}
	if ($backend eq 'sqlite')
	{
		my $err=system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "insertshadowsession", "$display", "$server", "$sid", "$shadreq_user");
		if ($err ne "ok")
		{
			die "$err: $x2go_lib_path/libx2go-server-db-sqlite3-wrapper insertshadowsession $display $server $sid $shadreq_user";
		}
	}
	syslog('debug', "db_insertshadowsession called, session ID: $sid, server: $server, session ID: $sid, shadowing requesting user: $shadreq_user");
}

sub db_createsession
{
	my $sid=shift or die "argument \"session_id\" missed";
	my $cookie=shift or die"argument \"cookie\" missed";
	my $pid=shift or die"argument \"pid\" missed";
	my $client=shift or die"argument \"client\" missed";
	my $gr_port=shift or die"argument \"gr_port\" missed";
	my $snd_port=shift or die"argument \"snd_port\" missed";
	my $fs_port=shift or die"argument \"fs_port\" missed";
	my $tekictrl_port=shift or die"argument \"tekictrl_port\" missed";
	my $tekidata_port=shift or die"argument \"tekidata_port\" missed";
	if ($backend eq 'postgres')
	{
		X2Go::Server::DB::PostgreSQL::db_createsession($sid, $cookie, $pid, $client, $gr_port, $snd_port, $fs_port, $tekictrl_port, $tekidata_port);
	}
	if ($backend eq 'sqlite')
	{
		my $err= system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "createsession", "$sid", "$cookie", "$pid", "$client", "$gr_port", "$snd_port", "$fs_port", "$tekictrl_port", "$tekidata_port");
		if ($err ne "ok")
		{
			die $err;
		}
	}
	syslog('debug', "db_createsession called, session ID: $sid, cookie: $cookie, client: $client, pid: $pid, graphics port: $gr_port, sound port: $snd_port, file sharing port: $fs_port. telekinesis ctrl port: $tekictrl_port, telekinesis data port: $tekidata_port");
}

sub db_createshadowsession
{
	my $sid=shift or die "argument \"session_id\" missed";
	my $cookie=shift or die"argument \"cookie\" missed";
	my $pid=shift or die"argument \"pid\" missed";
	my $client=shift or die"argument \"client\" missed";
	my $gr_port=shift or die"argument \"gr_port\" missed";
	my $snd_port=shift or die"argument \"snd_port\" missed";
	my $fs_port=shift or die"argument \"fs_port\" missed";
	my $shadreq_user=shift or die "argument \"shadreq_user\" missed";
	if ($backend eq 'postgres')
	{
		# for PostgreSQL we can use the normal db_createsession code...
		X2Go::Server::DB::PostgreSQL::db_createsession($sid, $cookie, $pid, $client, $gr_port, $snd_port, $fs_port, -1, -1);
	}
	if ($backend eq 'sqlite')
	{
		my $err=system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "createshadowsession", "$sid", "$cookie", "$pid", "$client", "$gr_port", "$snd_port", "$fs_port", "$shadreq_user");
		if ($err ne "ok")
		{
			die $err;
		}
	}
	syslog('debug', "db_createshadowsession called, session ID: $sid, cookie: $cookie, client: $client, pid: $pid, graphics port: $gr_port, sound port: $snd_port, file sharing port: $fs_port, shadowing requesting user: $shadreq_user");
}

sub db_insertport
{
	my $server=shift or die "argument \"server\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	my $sshport=shift or die "argument \"port\" missed";
	if ($backend eq 'postgres')
	{
		X2Go::Server::DB::PostgreSQL::db_insertport($server, $sid, $sshport);
	}
	if ($backend eq 'sqlite')
	{
		my $err=system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "insertport", "$server", "$sid", "$sshport");
		if ($err ne "ok")
		{
			die $err;
		}
	}
	syslog('debug', "db_insertport called, session ID: $sid, server: $server, SSH port: $sshport");
}

sub db_rmport
{
	my $server=shift or die "argument \"server\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	my $sshport=shift or die "argument \"port\" missed";
	if ($backend eq 'postgres')
	{
		X2Go::Server::DB::PostgreSQL::db_rmport($server, $sid, $sshport);
	}
	if ($backend eq 'sqlite')
	{
		system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "rmport", "$server", "$sid", "$sshport");
	}
	syslog('debug', "db_rmport called, session ID: $sid, server: $server, SSH port: $sshport");
}

sub db_resume
{
	my $client=shift or die "argument \"client\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	my $gr_port=shift or die "argument \"gr_port\" missed";
	my $snd_port=shift or die "argument \"snd_port\" missed";
	my $fs_port=shift or die "argument \"fs_port\" missed";
	my $tekictrl_port=shift or die"argument \"tekictrl_port\" missed";
	my $tekidata_port=shift or die"argument \"tekidata_port\" missed";
	if ($backend eq 'postgres')
	{
		X2Go::Server::DB::PostgreSQL::db_resume($client, $sid, $gr_port, $snd_port, $fs_port, $tekictrl_port, $tekidata_port);
	}
	if ($backend eq 'sqlite')
	{
		system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "resume", "$client", "$sid", "$gr_port", "$snd_port", "$fs_port", "$tekictrl_port", "$tekidata_port");
	}
	syslog('debug', "db_resume called, session ID: $sid, client: $client, gr_port: $gr_port, sound_port: $snd_port, fs_port: $fs_port, telekinesis ctrl port: $tekictrl_port, telekinesis data port: $tekidata_port");
}

sub db_changestatus
{
	my $status=shift or die "argument \"status\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	if ($backend eq 'postgres')
	{
		X2Go::Server::DB::PostgreSQL::db_changestatus($status, $sid);
	}
	if ($backend eq 'sqlite')
	{
		system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "changestatus", "$status", "$sid");
	}
	syslog('debug', "db_changestatus called, session ID: $sid, new status: $status");
}

sub db_getstatus
{
	my $sid=shift or die "argument \"session_id\" missed";
	my $status='';
	if ($backend eq 'postgres')
	{
		$status = X2Go::Server::DB::PostgreSQL::db_getstatus($sid);
	}
	if ($backend eq 'sqlite')
	{
		$status=system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "getstatus", "$sid");
	}
	syslog('debug', "db_getstatus called, session ID: $sid, return value: $status");
	return $status;
}

sub db_getdisplays
{
	my @displays;
	#ignore $server
	my $server=shift or die "argument \"server\" missed";
	if ($backend eq 'postgres')
	{
		@displays = X2Go::Server::DB::PostgreSQL::db_getdisplays($server);
	}
	if ($backend eq 'sqlite')
	{
		@displays = split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "getdisplays", "$server"));
	}
	my $log_retval = join(" ", @displays);
	syslog('debug', "db_getdisplays called, server: $server; return value: $log_retval");
	return @displays;
}

sub db_getports
{
	my @ports;
	#ignore $server
	my $server=shift or die "argument \"server\" missed";
	if ($backend eq 'postgres')
	{
		@ports = X2Go::Server::DB::PostgreSQL::db_getports($server);
	}
	if ($backend eq 'sqlite')
	{
		@ports = split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "getports", "$server"));
	}
	my $log_retval = join(" ", @ports);
	syslog('debug', "db_getports called, server: $server; return value: $log_retval");
	return @ports;
}

sub db_getservers
{
	my @servers;
	if ($backend eq 'postgres')
	{
		@servers = X2Go::Server::DB::PostgreSQL::db_getservers();
	}
	if ($backend eq 'sqlite')
	{
		@servers = split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "getservers"));
	}
	my $log_retval = join(" ", @servers);
	syslog('debug', "db_getservers called, return value: $log_retval");
	return @servers;
}

sub db_getagent
{
	my $agent;
	my $sid=shift or die "argument \"session_id\" missed";
	if ($backend eq 'postgres')
	{
		$agent = X2Go::Server::DB::PostgreSQL::db_getagent($sid);
	}
	if($backend eq 'sqlite')
	{
		$agent=system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "getagent", "$sid");
	}
	syslog('debug', "db_getagent called, session ID: $sid; return value: $agent");
	return $agent;
}

sub db_getdisplay
{
	my $display;
	my $sid=shift or die "argument \"session_id\" missed";
	if ($backend eq 'postgres')
	{
		$display = X2Go::Server::DB::PostgreSQL::db_getdisplay($sid);
	}
	if ($backend eq 'sqlite')
	{
		$display=system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "getdisplay", "$sid");
	}
	syslog('debug', "db_getdisplay called, session ID: $sid; return value: $display");
	return $display;
}

sub db_listhistory
{
	my $server=shift or die "argument \"server\" missed";
	if ($backend eq 'postgres')
	{
		return X2Go::Server::DB::PostgreSQL::db_listhistory($server);
	}
	if ($backend eq 'sqlite')
	{
		return split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "listhistory", "$server"));
	}
}

sub db_listhistory_all
{
	if ($backend eq 'postgres')
	{
		return X2Go::Server::DB::PostgreSQL::db_listhistory_all();
	}
	if ($backend eq 'sqlite')
	{
		return split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "listhistory_all"));
	}
}

sub db_listsessions
{
	my $server=shift or die "argument \"server\" missed";
	if ($backend eq 'postgres')
	{
		return X2Go::Server::DB::PostgreSQL::db_listsessions($server);
	}
	if ($backend eq 'sqlite')
	{
		return split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "listsessions", "$server"));
	}
}

sub db_listsessions_all
{
	if($backend eq 'postgres')
	{
		return X2Go::Server::DB::PostgreSQL::db_listsessions_all();
	}
	if ($backend eq 'sqlite')
	{
		return split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "listsessions_all"));
	}
}

sub db_listshadowsessions
{
	my $server=shift or die "argument \"server\" missed";
	if ($backend eq 'postgres')
	{
		return X2Go::Server::DB::PostgreSQL::db_listshadowsessions($server);
	}
	if ($backend eq 'sqlite')
	{
		return split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "listshadowsessions", "$server"));
	}
}

sub db_listshadowsessions_all
{
	if($backend eq 'postgres')
	{
		return X2Go::Server::DB::PostgreSQL::db_listshadowsessions_all();
	}
	if ($backend eq 'sqlite')
	{
		return split("\n",system_capture_merged_output("$x2go_lib_path/libx2go-server-db-sqlite3-wrapper", "listshadowsessions_all"));
	}
}
