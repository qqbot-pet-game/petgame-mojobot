use FindBin qw($Bin);
use lib "$Bin";

use Mojo::Webqq;
use Mojo::Util qw(md5_sum);
use Getopt::Std;

use vars qw($opt_p $opt_o $opt_q $opt_r $opt_d);
getopts('p:o:q:r:d');
# p: port; o: report_port; q: qq; r: qrcode_path; d: debug

my $qq = $opt_q ? int($opt_q) : 985388576;     #登录的QQ号
my $pwd = "aa";                                  #使用帐号密码方式登录时需要
my $pwd_md5 = md5_sum($pwd);                     #得到原始密码的32位长度md5

my $port = $opt_p ? int($opt_p) : 30000;
my $report_port = $opt_o ? int($opt_o) : 30001;
my $qrcode_path = $opt_r ? $opt_r : "./v.png";

my $debug = (defined $opt_d) ? 1 : 0;

#初始化一个客户端对象，设置登录的qq号
my $client=Mojo::Webqq->new(
    ua_debug    =>  0,         #是否打印详细的debug信息
    log_level   =>  "info",    #日志打印级别，debug|info|warn|error|fatal
    qq          =>  $qq,       #必选，登录的qq帐号，用于帐号密码登录或保存登录cookie使用
    pwd         =>  $pwd_md5,  #可选，如果选择帐号密码登录方式，必须指定帐号密码的md5值
    login_type  =>  "qrlogin", #"qrlogin"表示二维码登录，"login"表示帐号密码登录
    qrcode_path =>  $qrcode_path
);
#注意: 腾讯可能已经关闭了帐号密码的登录方式，这种情况下只能使用二维码扫描登录

#客户端进行登录
$client->login(delay=>1); #请关闭帐号的密保功能，不支持密保登录

#客户端加载ShowMsg插件，用于打印发送和接收的消息到终端
$client->load("ShowMsg");

#设置接收消息事件的回调函数，在回调函数中对消息以相同内容进行回复
$client->on(receive_message=>sub{
    my ($client,$msg)=@_;
    # $msg->reply($msg->content); #已以相同内容回复接收到的消息
    #你也可以使用$msg->dump() 来打印消息结构
});

#ready事件触发时 表示客户端一切准备就绪：已经成功登录、已经加载完个人/好友/群信息等
#你的代码建议尽量写在 ready 事件中
$client->on(ready=>sub{
    my $client = shift;

    #你的代码写在此处 

});

if (defined $debug) {
    $client->on(input_qrcode=>sub{
        my $client = shift;
        system("open $qrcode_path");
    });
}

$client->load("+MyOpenqq",data=>{                                                 
    listen => [ {host=>"127.0.0.1",port=>$port}, ] , #监听的地址和端口，支持多个
    post_api=> "http://127.0.0.1:$report_port/post_api",
});

#客户端开始运行
$client->run();

#run相当于执行一个死循环，不会跳出循环之外
#所以run应该总是放在代码最后执行，并且不要在run之后再添加任何自己的代码了