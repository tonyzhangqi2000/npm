from __future__ import absolute_import, unicode_literals

import json
import requests
import click

DEVICE_ROLES = {
    'other':'其它',
    'printer':'打印机',
    'video':'视频设备',
    'workstation':'工作站',
    'laptop':'笔记本电脑',
    'tablet':'平板电脑',
    'phone':'手机',
    'tv':'智能电视',
    'networking':'网络设备',
    'wifi':'无线设备',
    'nas':'NAS存储',
    'multimedia':'多媒体设备',
    'iot':'物联网(IoT)设备',
}

OS_TYPES = {
    0: '其它',
    1: 'Linux',
    2: 'Windows',
    3: 'OSX',
    4: 'iOS',
    5: 'Android'
}

SITE_ATTRIBUTES = [
    {
        "multi": False,
        "resource_name": "Device",
        "description": "设备的生产厂商.",
        "display": True,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "vendor"
    },
    {
        "multi": True,
        "resource_name": "Device",
        "description": "设备的角色.",
        "display": True,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "role"
    },
    {
        "multi": False,
        "resource_name": "Device",
        "description": "设备是否是网关.",
        "display": True,
        "required": False,
        "constraints": {
            "valid_values": [
                "true",
                "false"
            ],
            "allow_empty": False
        },
        "name": "gateway"
    },
    {
        "multi": False,
        "resource_name": "Device",
        "description": "设备的操作系统.",
        "display": True,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "os_type"
    },
    {
        "multi": False,
        "resource_name": "Device",
        "description": "设备的名称(不一定是hostname).",
        "display": True,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "name"
    },
    {
        "multi": False,
        "resource_name": "Device",
        "description": "设备的IP地址.",
        "display": True,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "ip_addr"
    },
    {
        "multi": False,
        "resource_name": "Device",
        "description": "设备的IP版本.",
        "display": True,
        "required": False,
        "constraints": {
            "allow_empty": False,
            "valid_values": [
                "4",
                "6"
            ],

        },
        "name": "ip_ver"
    },
    {
        "multi": False,
        "resource_name": "Device",
        "description": "设备的创建时间.",
        "display": True,
        "required": False,
        "constraints": {
            "allow_empty": False
        },
        "name": "createtime"
    },
    {
        "multi": False,
        "resource_name": "Device",
        "description": "设备的更新时间.",
        "display": True,
        "required": False,
        "constraints": {
            "allow_empty": False
        },
        "name": "updatetime"
    },
    {
        "multi": False,
        "resource_name": "Device",
        "description": "设备的IP地址.",
        "display": True,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "ip_addr"
    },
    {
        "multi": False,
        "resource_name": "Device",
        "description": "设备所属单位.",
        "display": False,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "orgnization"
    },
    {
        "multi": False,
        "resource_name": "Device",
        "description": "设备所属部门.",
        "display": False,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "department"
    },
    {
        "multi": True,
        "resource_name": "Device",
        "description": "设备所属资产组.",
        "display": False,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "group"
    },
    {
        "multi": True,
        "resource_name": "Device",
        "description": "设备责任人.",
        "display": False,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "owner"
    },
    {
        "multi": True,
        "resource_name": "Device",
        "description": '设备的标签，用于扩展描述信息，例如：MacBook "Core i7" 1.4 12" (Mid-2017-18).',
        "display": True,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "tag"
    },
    {
        "multi": True,
        "resource_name": "Device",
        "description": "设备提供的的服务，例如：22/ssh.",
        "display": True,
        "required": False,
        "constraints": {
            "allow_empty": True
        },
        "name": "service"
    },
]

def get_sites(nsot, user):
    headers = {'X-NSoT-Email': user, 'content-type': 'application/json'}
    endpoint = '{}/sites/'.format(nsot)
    resp = requests.get(endpoint, headers=headers)
    if not resp.ok:
        raise Exception("{0}, {1}".format(resp.status_code, resp.text))
    return resp.json()

@click.group()
@click.option('-n', '--nsot', 'nsot', default="http://localhost:8990/api", help='nsot地址, 例如: http://localhost:8990/api')
@click.option('-u', '--user', 'user', default="admin@example.tld", help="nsot管理用户的email")
@click.pass_context
def cli(ctx, nsot, user):
    ctx.ensure_object(dict)
    ctx.obj['NSOT'] = nsot
    ctx.obj['USER'] = user
    print()

@cli.command()
@click.pass_context
def ls(ctx):
    nsot = ctx.obj['NSOT']
    user = ctx.obj['USER']

    for s in get_sites(nsot, user):
        click.echo(s)

@cli.command()
@click.argument('site', default="app")
@click.pass_context
def init(ctx, site):
    nsot = ctx.obj['NSOT']
    user = ctx.obj['USER']
    headers = {'X-NSoT-Email': user, 'content-type': 'application/json'}

    site_id = -1
    for s in get_sites(nsot, user):
        if s['name'] == site:
            site_id = s['id']

    if site_id == -1:
        endpoint = '{}/sites/'.format(nsot)
        resp = requests.post(endpoint, headers=headers, data=json.dumps({'name': site}))
        if not resp.ok:
            raise Exception("{0}, {1}".format(resp.status_code, resp.text))
        site_id = resp.json()['id']

    for attrib in SITE_ATTRIBUTES:
        endpoint = nsot + '/attributes/?name={}'.format(attrib['name'])
        resp = requests.get(endpoint, headers=headers)
        if not resp.ok:
            raise Exception("{0}, {1}".format(resp.status_code, resp.text))

        if not resp.json():
            attrib['site_id'] = site_id
            endpoint = nsot + '/attributes/'
            resp = requests.post(endpoint, headers=headers, data=json.dumps(attrib))
            if not resp.ok:
                raise Exception("{0}, {1}".format(resp.status_code, resp.text))

@cli.command()
@click.argument('site', default="app")
@click.pass_context
def drop(ctx, site):
    nsot = ctx.obj['NSOT']
    user = ctx.obj['USER']
    headers = {'X-NSoT-Email': user, 'content-type': 'application/json'}

    site_id = -1
    for s in get_sites(nsot, user):
        if s['name'] == site:
            site_id = s['id']

    if site_id == -1:
        click.echo("{}不存在！".format(site))
        return

    ## 清除site包含的所有资源
    for resource in ['devices', 'interfaces', 'networks']:
        endpoint = '{}/sites/{}/{}'.format(nsot, site_id, resource)
        resp = requests.get(endpoint, headers=headers)
        if not resp.ok:
            raise Exception("{0}, {1}".format(resp.status_code, resp.text))
        for item in resp.json():
            endpoint = '{}/{}/{}'.format(nsot, resource, item['id'])
            resp = requests.delete(endpoint, headers=headers)
            if not resp.ok:
                raise Exception("{0}, {1}".format(resp.status_code, resp.text))

    ## 删除属性
    for attrib in SITE_ATTRIBUTES:
        endpoint = nsot + '/attributes/?name={}'.format(attrib['name'])
        resp = requests.get(endpoint, headers=headers)
        if resp.ok and resp.json():
            endpoint = '{}/attributes/{}'.format(nsot, resp.json()[0]['id'])
            requests.delete(endpoint, headers=headers)

    ## 删除site
    endpoint = '{}/sites/{}'.format(nsot, site_id)
    resp = requests.delete(endpoint, headers=headers)
    if not resp.ok:
        raise Exception("{0}, {1}".format(resp.status_code, resp.text))

    click.echo("清理完成！")

if __name__ == '__main__':
    cli(obj={})
