

目标：进行 python 软件包的 rpm 打包工作，需要生成新的 SPEC 并进行 obs 构建

描述：vllm-specs 是一个 git 仓库，home:Sakura286:vLLM 则是 osc co 下来的 obs _service 脚本存放的文件夹

新建软件包的步骤：

一、 SPEC 创建

1. 在 vllm-specs 里，将 python-template 复制一份，重命名新产生的文件夹自身及spec名为对应的软件包名

2. spec 中需要对尖括号部分进行一些替换：

<srcname> 替换为对应的软件包名
<srcname_header> 为pypi名称的第一个字母
<version> 替换为我要求的版本，如果没有特殊要求，就使用最新的版本
<sha256> 为 Source0 中的链接所下载压缩包的 sha256，应该不需要下载，字符串的值在 pypi 上能找到
<summary> 与 <description> 需要你去该软件包对应的 github 仓库中的 about 与 readme 中找
<url> 为对应的 github 仓库链接
<license> 在对应的 pypi 页面上可以找到
<doc_file><license_file> 在源码的目录里找

3. 继续修改然后确定这个包是否为架构相关的包，然后看情况确定使用哪一个 Provides

4. 修改完后生成一个提交，内容类似“python-xxx: init”

5. 将提交 push 到默认远程仓库

二、触发 obs 构建

1. 进入 home:Sakura286:vLLM 中，使用`osc mkpac python-xxx`类似的命令创建新包

2. 进入新创建的文件夹，将其他包的 _service 文件复制过来，并且修改 `<param name="extract">...</param>` 部分，替换为对应包名

3. 使用`osc add *`命令来跟踪文件，然后用`osc ci -m "xxxxx"`来进行提交，触发自动构建

你如果有什么问题可以参考目录中其他的文件
