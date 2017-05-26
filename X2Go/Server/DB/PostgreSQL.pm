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

package X2Go::Server::DB::PostgreSQL;

=head1 NAME

X2Go::Server::DB::PostgreSQL - X2Go Session Database package for Perl (PostgreSQL backend)

=head1 DESCRIPTION

X2Go::Server::DB::PostgreSQL Perl package for X2Go::Server.

=cut

use strict;
use DBI;
use POSIX;
use Sys::Syslog qw( :standard :macros );

use X2Go::Log qw( loglevel );
use X2Go::Config qw( get_config get_sqlconfig );
use X2Go::Utils qw( sanitizer system_capture_stdout_output is_true );

setlogmask( LOG_UPTO(loglevel()) );

use base 'Exporter';

our @EXPORT=('db_listsessions','db_listsessions_all', 'db_getservers', 'db_getagent', 'db_resume', 'db_changestatus', 'db_getstatus',
             'db_getdisplays', 'db_insertsession', 'db_insertshadowsession', 'db_getports', 'db_insertport', 'db_rmport', 'db_createsession', 'db_insertmount',
             'db_getmounts', 'db_deletemount', 'db_getdisplay', 'dbsys_getmounts', 'dbsys_listsessionsroot',
             'dbsys_listsessionsroot_all', 'dbsys_rmsessionsroot', 'dbsys_storehistoryroot', 'dbsys_deletemounts', 'db_listshadowsessions','db_listshadowsessions_all');

my ($uname, $pass, $uid, $pgid, $quota, $comment, $gcos, $homedir, $shell, $expire) = getpwuid(getuid());

my $host;
my $port;
my $db="x2go_sessions";
my $dbpass;
my $dbuser;
my $sslmode;
my $with_TeKi;

sub init_db
{
	# the $Config is required later (see below...)
	my $Config = get_config;
	$with_TeKi = is_true($Config->param("telekinesis.enable"));

	if ( ! ( $dbuser and $dbpass ) )
	{
		my $SqlConfig = get_sqlconfig;
		my $x2go_lib_path=system_capture_stdout_output("x2gopath", "libexec");

		my $backend=$SqlConfig->param("backend");
		if ( $backend ne "postgres" )
		{
			die "X2Go server is not configured to use the PostgreSQL session db backend";
		}

		$host=$SqlConfig->param("postgres.host");
		$port=$SqlConfig->param("postgres.port");
		if (!$host)
		{
			$host='localhost';
		}
		if (!$port)
		{
			$port='5432';
		}
		my $passfile;
		if ($uname eq 'root')
		{
			$dbuser='x2godbuser';
			$passfile="/etc/x2go/x2gosql/passwords/x2goadmin";
		}
		else
		{
			$dbuser="x2gouser_$uname";
			$passfile="$homedir/.x2go/sqlpass";
		}
		$sslmode=$SqlConfig->param("postgres.ssl");
		if (!$sslmode)
		{
			$sslmode="prefer";
		}
		open (FL,"< $passfile") or die "Can't read password file $passfile<br><b>Use x2godbadmin on server to configure database access for user $uname</b><br>";
		$dbpass=<FL>;
		close(FL);
		chomp($dbpass);
	}
}

sub dbsys_rmsessionsroot
{
	init_db();
	my $sid=shift or die "argument \"session_id\" missed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", 
	                     "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("delete from sessions  where session_id='$sid'");
	$sth->execute() or die;
	$sth=$dbh->prepare("delete from used_ports where session_id='$sid'");
	$sth->execute() or die;
	$sth->finish();
	undef $dbh;
	return 1;
}

sub dbsys_storehistoryroot
{
	init_db();
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $init_time;
	my $server;
	my $client;
	my $uname;

	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", 
	                     "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;					 
	my $sth=$dbh->prepare("select server,
	                       init_time,
	                       client,
	                       uname
	                       from sessions
	                       where session_id=?");
	$sth->execute($sid) or die;

	my @data;
	if(@data = $sth->fetchrow_array){
		$server=@data[0];
		$init_time=@data[1];
		$client=@data[2];
		$uname=@data[3];
	}
	
	my $sth=$dbh->prepare("insert into sessions_history(session_id,uname,server,client,init_time,last_time) 
	values (?,?,?,?,?,now())");
	$sth->execute($sid,$uname,$server,$client,$init_time) or die;
	$sth->finish();
	
	undef $dbh;
	return 1;
}

sub dbsys_deletemounts
{
	init_db();
	my $sid=shift or die "argument \"session_id\" missed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("delete from mounts where session_id='$sid'");
	$sth->execute();
	$sth->finish();
	undef $dbh;
	return 1;
}

sub dbsys_listsessionsroot
{
	init_db();
	my $server=shift or die "argument \"server\" missed";
	my @strings;
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", 
	                     "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth;
	if ($with_TeKi) {
		$sth=$dbh->prepare("select agent_pid, session_id, display, server, status,
		                    to_char(init_time,'YYYY-MM-DD\"T\"HH24:MI:SS'),cookie,client,gr_port,
		                    sound_port,to_char(last_time,'YYYY-MM-DD\"T\"HH24:MI:SS'),uname,
		                    to_char(now()-init_time,'SSSS'),fs_port,tekictrl_port,tekidata_port  from sessions
		                    where server='$server'  order by status desc");
	} else {
		$sth=$dbh->prepare("select agent_pid, session_id, display, server, status,
		                    to_char(init_time,'YYYY-MM-DD\"T\"HH24:MI:SS'),cookie,client,gr_port,
		                    sound_port,to_char(last_time,'YYYY-MM-DD\"T\"HH24:MI:SS'),uname,
		                    to_char(now()-init_time,'SSSS'),fs_port from sessions
		                    where server='$server' order by status desc");
	}
	$sth->execute()or die;
	my @data;
	my $i=0;
	while (@data = $sth->fetchrow_array) 
	{
		@strings[$i++]=join('|',@data);
	}
	$sth->finish();
	undef $dbh;
	return @strings;
}

sub dbsys_listsessionsroot_all
{
	init_db();
	my @strings;
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth;
	if ($with_TeKi) {
		$sth=$dbh->prepare("select agent_pid, session_id, display, server, status,
		                    to_char(init_time,'YYYY-MM-DD\"T\"HH24:MI:SS'),cookie,client,gr_port,
		                    sound_port,to_char(last_time,'YYYY-MM-DD\"T\"HH24:MI:SS'),uname,
		                    to_char(now()-init_time,'SSSS'),fs_port,tekictrl_port,tekidata_port  from  sessions
		                    order by status desc");
	} else {
		$sth=$dbh->prepare("select agent_pid, session_id, display, server, status,
		                    to_char(init_time,'YYYY-MM-DD\"T\"HH24:MI:SS'),cookie,client,gr_port,
		                    sound_port,to_char(last_time,'YYYY-MM-DD\"T\"HH24:MI:SS'),uname,
		                    to_char(now()-init_time,'SSSS'),fs_port from  sessions
		                    order by status desc");
	}
	$sth->execute()or die;
	my @data;
	my $i=0;
	while (@data = $sth->fetchrow_array) 
	{
		@strings[$i++]=join('|',@data);
	}
	$sth->finish();
	undef $dbh;
	return @strings;
}

sub dbsys_getmounts
{
	init_db();
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my @mounts;
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("select client, path from mounts where session_id='$sid'");
	$sth->execute()or die;
	my @data;
	my $i=0;
	while (@data = $sth->fetchrow_array) 
	{
		@mounts[$i++]=join("|",@data);
	}
	$sth->finish();
	undef $dbh;
	return @mounts;
}

sub db_getmounts
{
	init_db();
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my @mounts;
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("select client, path from mounts_view where session_id='$sid'");
	$sth->execute()or die;
	my @data;
	my $i=0;
	while (@data = $sth->fetchrow_array) 
	{
		@mounts[$i++]=join("|",@data);
	}
	$sth->finish();
	undef $dbh;
	return @mounts;
}

sub db_deletemount
{
	init_db();
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $path=shift or die "argument \"path\" missed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("delete from mounts_view where session_id='$sid' and path='$path'");
	$sth->execute();
	$sth->finish();
	undef $dbh;
	return 1;
}

sub db_insertmount
{
	init_db();
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $path=shift or die "argument \"path\" missed";
	my $client=shift or die "argument \"client\" missed";
	my $res_ok=0;
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("insert into mounts (session_id,path,client) values  ('$sid','$path','$client')");
	$sth->execute();
	if (!$sth->err())
	{
		$res_ok = 1;
	}
	$sth->finish();
	undef $dbh;
	return $res_ok;
}

sub db_insertsession
{
	init_db();
	my $display=shift or die "argument \"display\" missed";
	$display = sanitizer('num', $display) or die "argument \"display\" malformed";
	my $server=shift or die "argument \"server\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("insert into sessions (display,server,uname,session_id) values ('$display','$server','$uname','$sid')");
	$sth->execute()or die $_;
	$sth->finish();
	undef $dbh;
	return 1;
}

sub db_insertshadowsession
{
	init_db();
	my $display=shift or die "argument \"display\" missed";
	$display = sanitizer('num', $display) or die "argument \"display\" malformed";
	my $server=shift or die "argument \"server\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $shadreq_user=shift or die "argument \"shadreq_user\" missed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("insert into sessions (display,server,uname,session_id) values ('$display','$server','$shadreq_user','$sid')");
	$sth->execute()or die $_;
	$sth->finish();
	undef $dbh;
	return 1;
}

sub db_createsession
{
	init_db();
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $cookie=shift or die"argument \"cookie\" missed";
	my $pid=shift or die"argument \"pid\" missed";
	$pid = sanitizer('num', $pid) or die "argument \"pid\" malformed";
	my $client=shift or die"argument \"client\" missed";
	my $gr_port=shift or die"argument \"gr_port\" missed";
	$gr_port = sanitizer('num', $gr_port) or die "argument \"gr_port\" malformed";
	my $snd_port=shift or die"argument \"snd_port\" missed";
	$snd_port = sanitizer('num', $snd_port) or die "argument \"snd_port\" malformed";
	my $fs_port=shift or die"argument \"fs_port\" missed";
	$fs_port = sanitizer('num', $fs_port) or die "argument \"fs_port\" malformed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth;
	if ($with_TeKi) {
		my $tekictrl_port=shift or die"argument \"tekictrl_port\" missed";
		$tekictrl_port = sanitizer('pnnum', $tekictrl_port) or die "argument \"tekictrl_port\" malformed";
		my $tekidata_port=shift or die"argument \"tekidata_port\" missed";
		$tekidata_port = sanitizer('pnnum', $tekidata_port) or die "argument \"tekidata_port\" malformed";
		$sth=$dbh->prepare("update sessions_view set status='R',last_time=now(),
		                    cookie='$cookie',agent_pid='$pid',client='$client',gr_port='$gr_port',
		                    sound_port='$snd_port',fs_port='$fs_port',tekictrl_port='$tekictrl_port',
		                    tekidata_port='$tekidata_port'
		                    where session_id='$sid'");
	} else {
		$sth=$dbh->prepare("update sessions_view set status='R',last_time=now(),
		                    cookie='$cookie',agent_pid='$pid',client='$client',gr_port='$gr_port',
		                    sound_port='$snd_port',fs_port='$fs_port'
		                    where session_id='$sid'");
	}
	$sth->execute() or die;
	$sth->finish();
	undef $dbh;
	return 1;
}

sub db_insertport
{
	init_db();
	my $server=shift or die "argument \"server\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $sshport=shift or die "argument \"port\" missed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("insert into used_ports (server,session_id,port) values  ('$server','$sid','$sshport')");
	$sth->execute()or die;
	$sth->finish();
	undef $dbh;
	return 1;
}

sub db_rmport
{
	init_db();
	my $server=shift or die "argument \"server\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $sshport=shift or die "argument \"port\" missed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("delete from used_ports where server='$server' and session_id='$sid' and port='$sshport'");
	$sth->execute()or die;
	$sth->finish();
	undef $dbh;
	return 1;
}

sub db_resume
{
	init_db();
	my $client=shift or die "argument \"client\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $gr_port=shift or die "argument \"gr_port\" missed";
	$gr_port = sanitizer('num', $gr_port) or die "argument \"gr_port\" malformed";
	my $snd_port=shift or die "argument \"sound_port\" missed";
	$snd_port = sanitizer('num', $snd_port) or die "argument \"snd_port\" malformed";
	my $fs_port=shift or die "argument \"fs_port\" missed";
	$fs_port = sanitizer('num', $fs_port) or die "argument \"fs_port\" malformed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth;
	if ($with_TeKi) {
		my $tekictrl_port=shift or die"argument \"tekictrl_port\" missed";
		$tekictrl_port = sanitizer('pnnum', $tekictrl_port) or die "argument \"tekictrl_port\" malformed";
		my $tekidata_port=shift or die"argument \"tekidata_port\" missed";
		$tekidata_port = sanitizer('pnnum', $tekidata_port) or die "argument \"tekidata_port\" malformed";
		$sth=$dbh->prepare("update sessions_view set last_time=now(),status='R',client='$client',gr_port='$gr_port',
		                    sound_port='$snd_port',fs_port='$fs_port',tekictrl_port='$tekictrl_port',
		                    tekidata_port='$tekidata_port' where session_id = '$sid'");
	} else {
		$sth=$dbh->prepare("update sessions_view set last_time=now(),status='R',client='$client',gr_port='$gr_port',
		                    sound_port='$snd_port',fs_port='$fs_port' where session_id = '$sid'");
	}
	$sth->execute()or die;
	$sth->finish();
	undef $dbh;
	return 1;
}

sub db_changestatus
{
	init_db();
	my $status=shift or die "argument \"status\" missed";
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("update sessions_view set last_time=now(),status='$status' where session_id = '$sid'");
	$sth->execute()or die;
	$sth->finish();
	undef $dbh;
	return 1;
}

sub db_getstatus
{
	init_db();
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $status='';
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("select status from sessions_view where session_id = '$sid'");
	$sth->execute($sid) or die;
	my @data;
	if (@data = $sth->fetchrow_array) 
	{
		$status=@data[0];
	}
	$sth->finish();
	undef $dbh;
	return $status;
}

sub db_getdisplays
{
	init_db();
	#ignore $server
	my $server=shift or die "argument \"server\" missed";
	my @displays;
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("select display from servers_view");
	$sth->execute()or die;
	my @data;
	my $i=0;
	while (@data = $sth->fetchrow_array) 
	{
		@displays[$i++]='|'.@data[0].'|';
	}
	$sth->finish();
	undef $dbh;
	return @displays;
}

sub db_getports
{
	init_db();
	my @ports;
	#ignore $server
	my $server=shift or die "argument \"server\" missed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("select port from ports_view");
	$sth->execute()or die;
	my @data;
	my $i=0;
	while (@data = $sth->fetchrow_array) 
	{
		@ports[$i++]='|'.@data[0].'|';
	}
	$sth->finish();
	undef $dbh;
	return @ports;
}

sub db_getservers
{
	init_db();
	my @servers;
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("select server,count(*) from servers_view where status != 'F' group by server");
	$sth->execute()or die;
	my @data;
	my $i=0;
	while (@data = $sth->fetchrow_array) 
	{
		@servers[$i++]=@data[0]." ".@data[1];
	}
	$sth->finish();
	undef $dbh;
	return @servers;
}

sub db_getagent
{
	init_db();
	my $agent;
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("select agent_pid from sessions_view
	                      where session_id ='$sid'");
	$sth->execute()or die;
	my @data;
	my $i=0;
	if (@data = $sth->fetchrow_array) 
	{
		$agent=@data[0];
	}
	$sth->finish();
	undef $dbh;
	return $agent;
}

sub db_getdisplay
{
	init_db();
	my $display;
	my $sid=shift or die "argument \"session_id\" missed";
	$sid = sanitizer('x2gosid', $sid) or die "argument \"session_id\" malformed";
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("select display from sessions_view
	                      where session_id ='$sid'");
	$sth->execute() or die;
	my @data;
	my $i=0;
	if (@data = $sth->fetchrow_array) 
	{
		$display=@data[0];
	}
	$sth->finish();
	undef $dbh;
	return $display;
}

sub db_listsessions
{
	init_db();
	my $server=shift or die "argument \"server\" missed";
	my @sessions;
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth;
	if ($with_TeKi) {
		$sth=$dbh->prepare("select agent_pid, session_id, display, server, status,
		                    to_char(init_time,'YYYY-MM-DD\"T\"HH24:MI:SS'), cookie, client, gr_port,
		                    sound_port, to_char( last_time, 'YYYY-MM-DD\"T\"HH24:MI:SS'), uname,
		                    to_char(now()- init_time,'SSSS'), fs_port, tekictrl_port, tekidata_port  from  sessions_view
		                    where status !='F' and server='$server' and
		                    (session_id not like '%XSHAD%') order by status desc");
	} else {
		$sth=$dbh->prepare("select agent_pid, session_id, display, server, status,
		                    to_char(init_time,'YYYY-MM-DD\"T\"HH24:MI:SS'), cookie, client, gr_port,
		                    sound_port, to_char( last_time, 'YYYY-MM-DD\"T\"HH24:MI:SS'), uname,
		                    to_char(now()- init_time,'SSSS'), fs_port  from  sessions_view
		                    where status !='F' and server='$server' and
		                    (session_id not like '%XSHAD%') order by status desc");
	}
	$sth->execute() or die;
	my @data;
	my $i=0;
	while (@data = $sth->fetchrow_array) 
	{
		@sessions[$i++]=join('|',@data);
	}
	$sth->finish();
	undef $dbh;
	return @sessions;
}

sub db_listsessions_all
{
	init_db();
	my @sessions;
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth;
	if ($with_TeKi) {
		$sth=$dbh->prepare("select agent_pid, session_id, display, server, status,
		                    to_char(init_time,'YYYY-MM-DD\"T\"HH24:MI:SS'), cookie, client, gr_port,
		                    sound_port, to_char( last_time, 'YYYY-MM-DD\"T\"HH24:MI:SS'), uname,
		                    to_char(now()- init_time,'SSSS'), fs_port, tekictrl_port, tekidata_port  from  sessions_view
		                    where status !='F'  and
		                    (session_id not like '%XSHAD%') order by status desc");
	} else {
		$sth=$dbh->prepare("select agent_pid, session_id, display, server, status,
		                    to_char(init_time,'YYYY-MM-DD\"T\"HH24:MI:SS'), cookie, client, gr_port,
		                    sound_port, to_char( last_time, 'YYYY-MM-DD\"T\"HH24:MI:SS'), uname,
		                    to_char(now()- init_time,'SSSS'), fs_port  from  sessions_view
		                    where status !='F'  and
		                    (session_id not like '%XSHAD%') order by status desc");
	}
	$sth->execute()or die;
	my @data;
	my $i=0;
	while (@data = $sth->fetchrow_array) 
	{
		@sessions[$i++]=join('|',@data);
	}
	$sth->finish();
	undef $dbh;
	return @sessions;
}

sub db_listshadowsessions
{
	init_db();
	my $server=shift or die "argument \"server\" missed";
	my @sessions;
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("select agent_pid, session_id, display, server, status,
	                      to_char(init_time,'YYYY-MM-DD\"T\"HH24:MI:SS'), cookie, client, gr_port,
	                      sound_port, to_char( last_time, 'YYYY-MM-DD\"T\"HH24:MI:SS'), uname,
	                      to_char(now()- init_time,'SSSS'), fs_port from  sessions_view
	                      where status !='F' and server='$server' and
	                      (session_id like '%XSHAD%') order by status desc");
	$sth->execute() or die;
	my @data;
	my $i=0;
	while (@data = $sth->fetchrow_array) 
	{
		@sessions[$i++]=join('|',@data);
	}
	$sth->finish();
	undef $dbh;
	return @sessions;
}

sub db_listshadowsessions_all
{
	init_db();
	my @sessions;
	my $dbh=DBI->connect("dbi:Pg:dbname=$db;host=$host;port=$port;sslmode=$sslmode", "$dbuser", "$dbpass",{AutoCommit => 1}) or die $_;
	my $sth=$dbh->prepare("select agent_pid, session_id, display, server, status,
	                      to_char(init_time,'YYYY-MM-DD\"T\"HH24:MI:SS'), cookie, client, gr_port,
	                      sound_port, to_char( last_time, 'YYYY-MM-DD\"T\"HH24:MI:SS'), uname,
	                      to_char(now()- init_time,'SSSS'), fs_port from  sessions_view
	                      where status !='F'  and
	                      (session_id is like '%XSHAD%') order by status desc");
	$sth->execute()or die;
	my @data;
	my $i=0;
	while (@data = $sth->fetchrow_array) 
	{
		@sessions[$i++]=join('|',@data);
	}
	$sth->finish();
	undef $dbh;
	return @sessions;
}

1;
