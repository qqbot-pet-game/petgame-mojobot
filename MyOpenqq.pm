use strict;

use FindBin qw($Bin);
use lib "$Bin";

use Mojo::Webqq::Server;
use MyFace;
package MyOpenqq;
$MyOpenqq::PRIORITY = 98;
my $server;
sub call{
    my $client = shift;
    my $data   =  shift;
    my $post_api = $data->{post_api} if ref $data eq "HASH";

    $client->info("loading plugin: MyOpenqq");

    my @msg_list = ();

    if(defined $post_api){
        $client->on(ready=>sub{
            my $client = shift;
            $client->http_post($post_api, "login ok");
        });
        $client->on(input_qrcode=>sub{
            my $client = shift;
            $client->http_post($post_api, "input qrcode");
        });
        $client->on(receive_message=>sub{
            my($client,$msg) = @_;
            return if $msg->type !~ /^message|group_message|discuss_message|sess_message$/;
            $client->http_post($post_api,json=>$msg->to_json_hash,sub{
                my($data,$ua,$tx) = @_;
                if($tx->success){
                    $client->debug("插件[".__PACKAGE__ ."]接收消息[".$msg->msg_id."]上报成功");
                }
                else{
                    $client->warn("插件[".__PACKAGE__ . "]接收消息[".$msg->msg_id."]上报失败: ".$tx->error->{message}); 
                }
            });
        });
    }

    # $client->on(ready=>sub{
    #     my $client = shift;
    #     $client->http_post($post_api, "login ok");
    # });
    $client->on(receive_message=>sub{
        my($client,$msg) = @_;
        return if $msg->type !~ /^message|group_message|discuss_message|sess_message$/;
        @msg_list = (@msg_list, $msg);
    });

    package MyOpenqq::App;
    use Encode;
    use Mojolicious::Lite;
    under sub {
        my $c = shift;
        if(ref $data eq "HASH" and ref $data->{auth} eq "CODE"){
            my $hash  = $c->req->params->to_hash;
            $client->reform_hash($hash);
            my $ret = 0;
            eval{
                $ret = $data->{auth}->($hash,$c);
            };
            $client->warn("插件[MyOpenqq]认证回调执行错误: $@") if $@;
            $c->render(text=>"auth failure",status=>403) if not $ret;
            return $ret;
        }
        else{return 1} 
    };
    get '/openqq/close' => sub {
        my $c = shift;
        $c->stop();
    };
    get '/openqq/get_user_info'     => sub {$_[0]->render(json=>$client->user->to_json_hash());};
    get '/openqq/get_friend_info'   => sub {
        my $c = shift;
        my $uid = $c->param("id");
        if (defined $uid) {
            my $friend = $client->search_friend(id=>$uid);
            unless (defined $friend) {
                $client->each_group(sub {
                    my ($client, $group) = @_;
                    $friend = $group->search_group_member(id=>$uid);
                    # last if (defined $friend);
                    return;
                });
            }
            if (defined $friend) {
                my $qq = $friend->qq;
            }
            if (defined $friend) { $c->render(json=>$friend->to_json_hash()); } 
            else { $c->render(json=>{code=>100,status=>"friend not found"}); }
        }
        else { $c->render(json=>[map {$_->to_json_hash()} @{$client->friend}]); }
    };
    get '/openqq/get_group_info'    => sub {
        my $c = shift;
        my($gid,$gcode)=($c->param("gid"),$c->param("gcode"));
        if ((defined $gid) || (defined $gcode)) {
            my $group = undef;
            if (defined $gid) { $group = $client->search_group(gid=>$gid); }
            if (defined $gcode) { $group = $client->search_group(gcode=>$gcode); }
            if (defined $group) {
                # my $gnumber = $group->gnumber;
                # my $owner = $group->gowner;
                # my $createtime = $group->gcreatetime;
                # my $owner_qq = $group->search_group_member(id=>$owner);
                # $group->nid = "${owner_qq}_${createtime}";
                $c->render(json=>$group->to_json_hash());
            }
            else { $c->render(json=>{code=>100,status=>"group not found"}); }
        }
        else { $c->render(json=>[map {$_->to_json_hash()} @{$client->group}]); }
    };
    get '/openqq/get_discuss_info'  => sub {$_[0]->render(json=>[map {$_->to_json_hash()} @{$client->discuss}]); };
    get '/openqq/get_recent_info'   => sub {$_[0]->render(json=>[map {$_->to_json_hash()} @{$client->recent}]);};
    get '/openqq/get_group_member_info' => sub {
        my $c = shift;
        my($gid,$gcode,$uid)=($c->param("gid"),$c->param("gcode"),$c->param("uid"));
        my $group = undef;
        my $member = undef;
        if (defined $gid) { $group = $client->search_group(gid=>$gid); }
        if (defined $gcode) { $group = $client->search_group(gcode=>$gcode); }
        if (defined $group) {
            $member = $group->search_group_member(id=>$uid);
            if ($member) { my $qq = $member->qq; }
            if (defined $member) { $c->render(json=>$member->to_json_hash()); }
            else { $c->render(json=>{code=>100,status=>"member not found"}); }
        }
        else { $c->render(json=>{code=>100,status=>"group not found"}); }
    };
    any [qw(GET POST)] => '/openqq/send_message'         => sub{
        my $c = shift;
        my($id,$qq,$content)=($c->param("id"),$c->param("qq"),$c->param("content"));
        my $friend = $client->search_friend(id=>$id,qq=>$qq);
        if(defined $friend){
            $c->render_later;
            $client->send_message($friend,encode("utf8",$content),sub{
                my $msg= $_[1];
                $msg->cb(sub{
                    my($client,$msg,$status)=@_;
                    $c->render(json=>{msg_id=>$msg->msg_id,code=>$status->code,status=>decode("utf8",$status->msg)});  
                });
                $msg->msg_from("api");
            });
        }
        else{$c->render(json=>{msg_id=>undef,code=>100,status=>"friend not found"});}
    };
    any [qw(GET POST)] => 'openqq/send_group_message'    => sub{
        my $c = shift;
        my($gid,$gnumber,$content)=($c->param("gid"),$c->param("gnumber"),$c->param("content"));
        my $group = $client->search_group(gid=>$gid,gnumber=>$gnumber,);
        if(defined $group){
            $c->render_later;
            $client->send_group_message($group,encode("utf8",$content),sub{
                my $msg = $_[1];
                $msg->cb(sub{
                    my($client,$msg,$status)=@_;
                    $c->render(json=>{msg_id=>$msg->msg_id,code=>$status->code,status=>decode("utf8",$status->msg)});
                });
                $msg->msg_from("api");
            });
        }
        else{$c->render(json=>{msg_id=>undef,code=>101,status=>"group not found"});}
    };
    any [qw(GET POST)] => 'openqq/send_discuss_message'  => sub{
        my $c = shift;
        my($did,$content)=($c->param("did"),$c->param("content"));
        my $discuss = $client->search_discuss(did=>$did);
        if(defined $discuss){
            $c->render_later;
            $client->send_discuss_message($discuss,encode("utf8",$content),sub{
                my $msg = $_[1];
                $msg->cb(sub{
                    my($client,$msg,$status)=@_;
                    $c->render(json=>{msg_id=>$msg->msg_id,code=>$status->code,status=>decode("utf8",$status->msg)});
                });
                $msg->msg_from("api");
            });
        }
        else{$c->render(json=>{msg_id=>undef,code=>102,status=>"discuss not found"});}
    };
    any [qw(GET POST)] => '/openqq/send_sess_message'    => sub{
        my $c = shift;
        my($gid,$gnumber,$did,$qq,$id,$content)=
        ($c->param("gid"),$c->param("gnumber"),$c->param("did"),$c->param("qq"),$c->param("id"),$c->param("content"));
        if(defined $gid or defined $gnumber){
            my $group = $client->search_group(gid=>$gid,gnumber=>$gnumber);
            my $member = defined $group?$group->search_group_member(qq=>$qq,id=>$id):undef;
            if(defined $member){
                $c->render_later;
                $client->send_sess_message($member,encode("utf8",$content),sub{
                    my $msg = $_[1];
                    $msg->cb(sub{
                        my($client,$msg,$status)=@_;
                        $c->render(json=>{msg_id=>$msg->msg_id,code=>$status->code,status=>decode("utf8",$status->msg)});
                    });
                    $msg->msg_from("api");
                });
            }
            else{$c->render(json=>{msg_id=>undef,code=>103,status=>"group member not found"});}
        }
        elsif(defined $did){
            my $discuss = $client->search_discuss(did=>$did);
            my $member = defined $discuss?$discuss->search_discuss_member(qq=>$qq,id=>$id):undef;
            if(defined $member){
                $c->render_later;
                $client->send_sess_message($member,encode("utf8",$content),sub{
                    my $msg = $_[1];
                    $msg->cb(sub{
                        my($client,$msg,$status)=@_;
                        $c->render(json=>{msg_id=>$msg->msg_id,code=>$status->code,status=>decode("utf8",$status->msg)});
                    });
                    $msg->msg_from("api");
                });
            }
            else{$c->render(json=>{msg_id=>undef,code=>104,status=>"discuss member not found"});}
        }
        else{$c->render(json=>{msg_id=>undef,code=>105,status=>"discuss member or group member  not found"});}
    };
    any '/*whatever'  => sub{whatever=>'',$_[0]->render(text=>"request error",status=>403)};
    package MyOpenqq;
    $server = Mojo::Webqq::Server->new();   
    $server->app($server->build_app("MyOpenqq::App"));
    $server->app->secrets("hello world");
    $server->app->log($client->log);
    if(ref $data eq "ARRAY"){#旧版本兼容性
        $server->listen($data);
    }
    elsif(ref $data eq "HASH" and ref $data->{listen} eq "ARRAY"){
        $server->listen($data->{listen}) ;
    }
    $server->start;
}
1;