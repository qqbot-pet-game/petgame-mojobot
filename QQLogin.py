# -*- coding: utf-8 -*-

# Code by Yinzo:        https://github.com/Yinzo
# Origin repository:    https://github.com/Yinzo/SmartQQBot

import random
import time
import datetime
import re
import json
import thread
import logging
import traceback
import requests
import socket

import sys, os

from Configs import *
from Msg import *
from Notify import *
from HttpClient import *
from HttpServer import HttpServer

logging.basicConfig(
    filename='smartqq.log',
    level=logging.DEBUG,
    format='%(asctime)s  %(filename)s[line:%(lineno)d] %(levelname)s %(message)s',
    datefmt='%a, %d %b %Y %H:%M:%S'
)

root_path = os.path.split(os.path.realpath(__file__))[0] + '/'

def close_port(port):
    try:
        s = socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        s.settimeout(1)
        s.connect(('127.0.0.1',int(port)))
        s.shutdown(2)
    except:
        pass
    return True

def date_to_millis(d):
    return int(time.mktime(d.timetuple())) * 1000

def startMojoQQ(qq, report_port, mojo_port, qrcode_path, operator):
    operator.mojo_on = True
    mojo_qq_path = os.path.realpath(root_path + 'MojoQQ.pl')
    os.system("perl {0} -p {1} -o {2} -q {3} -r {4}".format(mojo_qq_path, mojo_port, report_port, qq, qrcode_path))
    operator.mojo_off = True
    operator.login_fail = True

class QQ:
    def __init__(self, sys_paras):
        self.sys_paras = sys_paras
        self.default_config = DefaultConfigs()
        self.last_refresh = time.time()
        self.refresh_interval = int(self.default_config.conf.get("global", "refresh_interval"))
        self.qrcode_path = sys_paras['qrcode_path'] if sys_paras['qrcode_path'] else self.default_config.conf.get("global", "qrcode_path")  # QRCode保存路径
        self.http_server = None
        self.mojo_on = False
        self.mojo_off = False
        self.account = None
        self.username = None
        self.login_ok = False
        self.login_fail = False
        self.login_input_qrcode = False
        self.login_input_qrcode_triggered = False
        self.msg_handler = None
        self.msg_list = []
        self.mojo_port = int(self.sys_paras['mojo_port'])

    def login_by_qrcode(self):
        logging.info("Requesting the login pages...")
        qrcode_path = self.sys_paras['qrcode_path']
        if os.path.exists(qrcode_path): os.remove(qrcode_path)
        close_port(self.sys_paras['report_port'])
        self.http_server = HttpServer(self.sys_paras['report_port'], 'OK')
        thread.start_new_thread(self.wait_msg, ())
        thread.start_new_thread(startMojoQQ, (self.sys_paras['qq_code'], self.sys_paras['report_port'], self.sys_paras['mojo_port'], qrcode_path, self))
        wait_time = 300
        detect_interval = 0.01
        i = 0
        while i < wait_time / detect_interval:
            if self.login_fail: return False
            elif self.login_ok: break
            elif self.login_input_qrcode:
                self.login_input_qrcode = False
                continue
            time.sleep(detect_interval)
            i += 1
        r = requests.get('http://127.0.0.1:' + str(self.mojo_port) + '/openqq/get_user_info')
        if r.status_code != 200: return False
        try:
            r_data = json.loads(r.text)
            self.account = r_data['account']
            self.username = r_data['nick']
        except:
            return False
        logging.info("QQ：{0} login successfully, Username：{1}".format(self.account, self.username))
        return True

    def wait_msg(self):
        self.http_server.run(self.msg_process)

    def msg_process(self, data):
        try:
            lines = data.split('\n')
            uri = lines[1].split(' ')[1]
            msg = lines[-1]
            if (msg == "login ok"):
                self.login_ok = True
                return True
            elif (msg == "login failed"):
                self.login_fail = True
                return True
            elif (msg == "input qrcode"):
                self.login_input_qrcode = True
                return True
            msg = json.loads(msg)
            pm_list = []
            sess_list = []
            group_list = []
            notify_list = []
            ret_type = msg['type']
            if ret_type == 'message' and False:
                pm_list.append(PmMsg(msg))
            elif ret_type == 'group_message' and True:
                msg['group_code'] = self.get_group_info(gid=msg['group_id'])['gcode']
                group_list.append(GroupMsg(msg))
            elif ret_type == 'sess_message' and False:
                sess_list.append(SessMsg(msg))
            elif ret_type == 'input_notify' and False:
                notify_list.append(InputNotify(msg))
            elif ret_code == 'kick_message' and False:
                notify_list.append(KickMessage(msg))
            else:
                logging.warning("unknown message type: " + str(ret_type) + "details:    " + str(msg))

            group_list.sort(key=lambda x: x.seq)
            self.msg_list += pm_list + sess_list + group_list + notify_list
            if not self.msg_list:
                return False
            return True
        except:
            logging.warning("An error has occured when handling message. Error traceback:\n" + traceback.format_exc())
            return False
        return True

    def check_msg(self):
        if self.mojo_off:
            return None
        msg_list = [i for i in self.msg_list]
        msg_cnt = len(msg_list)
        if msg_cnt == 0:
            return []
        else:
            self.msg_list = self.msg_list[msg_cnt:]
            return msg_list

    def sendGroupMessage(self, gid, content):
        r = requests.post("http://127.0.0.1:" + str(self.mojo_port) + "/openqq/send_group_message", { 'gid': gid, 'content': content })
        return (r.status_code == 200)

    def close(self):
        if self.mojo_on and not self.mojo_off:
            r = requests.get("http://127.0.0.1:" + str(self.mojo_port) + "/openqq/close")
            if not r.status_code == 200: print "close mojo failed"
        try:
            self.lisfd.shutdown(socket.SHUT_RD)
        except:
            print "shutdown server failed"
            pass

    # 查询QQ号，通常首次用时0.2s，以后基本不耗时
    def get_account(self, msg):
        assert isinstance(msg, (Msg, Notify)), "function get_account received a not Msg or Notify parameter."

        if isinstance(msg, (PmMsg, SessMsg, InputNotify)):
            # 如果消息的发送者的真实QQ号码不在FriendList中,则自动去取得真实的QQ号码并保存到缓存中
            tuin = msg.from_uin
            account = self.uin_to_account(tuin)
            return account

        elif isinstance(msg, GroupMsg):
            return str(msg.info_seq).join("[]") + str(self.uin_to_account(msg.send_uin))

    def uin_to_account(self, tuin):
        uin_str = str(tuin)
        r = requests.get("http://127.0.0.1:" + str(self.mojo_port) + "/openqq/get_friend_info?id={0}".format(uin_str))
        if r.status_code == 200:
            data = r.json()
            if not ('code' in data and data['code'] != 0):
                return data['qq']
        return None

    # 查询详细信息
    def get_friend_info(self, msg):
        # assert isinstance(msg, (Msg, Notify)), "function get_account received a not Msg or Notify parameter."
        assert isinstance(msg, (PmMsg, GroupMsg)), "function get_friend_info received a not PmMsg or GroupMsg parameter"
        tuin = ""
        # if isinstance(msg, (PmMsg, SessMsg, InputNotify)):
        if isinstance(msg, (PmMsg)):
            tuin = str(msg.from_uin)
        elif isinstance(msg, GroupMsg):
            tuin = str(msg.send_uin)
        else:
            return None
        r = requests.get("http://127.0.0.1:" + str(self.mojo_port) + "/openqq/get_friend_info?id={0}".format(tuin))
        if r.status_code == 200:
            data = r.json()
            if not ('code' in data and data['code'] != 0):
                return data
        return None
    
    # 查询群信息
    def get_group_info(self, msg = None, gid = None, gcode = None):
        query_str = ""
        if msg:
            gcode = str(msg.group_code)
            query_str += "gcode={0}".format(gcode)
        elif gid:
            query_str += "gid={0}".format(gid)
        elif gcode:
            query_str += "gcode={0}".format(gcode)
        else:
            return None
        r = requests.get("http://127.0.0.1:" + str(self.mojo_port) + "/openqq/get_group_info?" + query_str)
        if r.status_code == 200:
            data = r.json()
            if not ('code' in data and data['code'] != 0):
                data['nid'] = "{0}_{1}".format(self.uin_to_account(data['gowner']), data['gcreatetime'])
                return data
        return None

    def get_groupnames(self):
        r = requests.get("http://127.0.0.1:" + str(self.mojo_port) + "/openqq/get_group_info")
        if r.status_code == 200:
            data = r.json()
            if not ('code' in data and data['code'] != 0):
                return [{ "name": item['gname'], "code": item['gcode']} for item in data]
        return None
        

