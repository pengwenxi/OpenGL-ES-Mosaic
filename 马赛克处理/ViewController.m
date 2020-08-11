//
//  ViewController.m
//  滤镜处理
//
//  Created by 彭文喜 on 2020/8/7.
//  Copyright © 2020 彭文喜. All rights reserved.
//

#import "ViewController.h"
#import <GLKit/GLKit.h>

typedef struct {
    GLKVector3 positionCoord;//(x,y,z)
    GLKVector2 textureCoord; //(U,V)
}SenceVertex;

#define Tag 100
@interface ViewController ()

@property(nonatomic,assign)SenceVertex *vertices;
@property(nonatomic,strong)EAGLContext *context;
//用于刷新屏幕
@property(nonatomic,strong)CADisplayLink *displayLink;
//开始的时间戳
@property(nonatomic,assign)NSTimeInterval startTimeVal;
//着色器程序
@property(nonatomic,assign)GLuint program;
//顶点缓存
@property(nonatomic,assign)GLuint vertexBuffer;
//纹理 ID
@property(nonatomic,assign)GLuint textureID;

@property(nonatomic,strong)UIScrollView *scrollView;

@end

@implementation ViewController
- (void)dealloc {
    //1.上下文释放
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
    //顶点缓存区释放
    if (_vertexBuffer) {
        glDeleteBuffers(1, &_vertexBuffer);
        _vertexBuffer = 0;
    }
    //顶点数组释放
    if (_vertices) {
        free(_vertices);
        _vertices = nil;
    }
}
-(void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    //移除
    if(self.displayLink){
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    //1、创建滤镜工具栏
    [self setupFilterBar];
    
    //2、滤镜处理初始化
    [self filterInit];
    //3、开始一个滤镜动画
    [self startFilterAnimation];
}

//创建滤镜栏
-(void)setupFilterBar{
    CGFloat filterBarWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat filterBarHeight = 100;
    CGFloat filterBarY = [UIScreen mainScreen].bounds.size.height - filterBarHeight;

    
    NSArray *dataList = @[@"无",@"灰度",@"颠倒",@"马赛克",@"马赛克2",@"马赛克3"];

    
    UIScrollView *scrollView = [[UIScrollView alloc]initWithFrame:CGRectMake(0, filterBarY, filterBarWidth, filterBarHeight)];
    
    scrollView.contentSize = CGSizeMake(600, filterBarHeight);
    scrollView.backgroundColor = [UIColor blackColor];
    scrollView.bounces = NO;
    [self.view addSubview:scrollView];
    
    self.scrollView = scrollView;
    
    for (int i = 0; i<6; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        [btn setTitle:dataList[i] forState:UIControlStateNormal];
        btn.tag = Tag+i;
        [btn setBackgroundColor:UIColor.whiteColor];
        [btn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        [btn setFrame:CGRectMake(100*i+10, 0, 80, filterBarHeight)];
        [btn addTarget:self action:@selector(changeTitle:) forControlEvents:UIControlEventTouchUpInside];
        [scrollView addSubview:btn];
    }
    
}


-(void)filterInit{
    //1.初始化上下文并设置为当前上下文
    self.context = [[EAGLContext alloc]initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    [EAGLContext setCurrentContext:self.context];
    
    //2.开辟顶点数组内存空间
    self.vertices = malloc(sizeof(SenceVertex)*4);
    //3.初始化顶点0，1，2，3的顶点坐标和纹理坐标
    self.vertices[0] = (SenceVertex){{-1,1,0},{0,1}};
    self.vertices[1] = (SenceVertex){{-1,-1,0},{0,0}};
    self.vertices[2] = (SenceVertex){{1,1,0},{1,1}};
    self.vertices[3] = (SenceVertex){{1,-1,0},{1,0}};
    
    //4.创建图层
    CAEAGLLayer *layer = [[CAEAGLLayer alloc]init];
    //设置图层frame
    layer.frame = CGRectMake(0, 100, self.view.frame.size.width, self.view.frame.size.width);
    //设置图层的scale
    layer.contentsScale = [[UIScreen mainScreen]scale];
    [self.view.layer addSublayer:layer];
    
    //5.绑定渲染缓冲区
    [self bindRenderLayer:layer];
    //6。获取处理图片
    NSString *imagePath = [[NSBundle mainBundle]pathForResource:@"2" ofType:@"jpg"];
    //NSString *imagePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"kunkun.jpg"];
    //读取图片
    UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
    //将jpg转成纹理图片
    GLuint texture2D = [self createTextureWithImage:image];
    
    //设置纹理ID
    self.textureID = texture2D;
    
    //7.设置视口
    glViewport(0, 0, self.drawableWidth, self.drawableHeight);
    
    //8.设置顶点缓存区
    GLuint vertexBuffer;
    glGenBuffers(1, &vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    GLsizeiptr bufferSizeBytes = sizeof(SenceVertex) * 4;
    glBufferData(GL_ARRAY_BUFFER, bufferSizeBytes, self.vertices, GL_STATIC_DRAW);

    //9.设置默认着色器
    [self setupNormalShaderProgram];
    
    //10.将顶点缓存保存，退出时才释放
    self.vertexBuffer = vertexBuffer;
}



//绑定渲染缓冲区和帧缓冲区
-(void)bindRenderLayer:(CALayer <EAGLDrawable> *)layer{
    //1.渲染缓冲区，帧缓冲区
    GLuint renderBuffer;
    GLuint frameBuffer;
    //2.获取帧渲染缓存区名称，绑定渲染缓冲区以及将渲染缓存区与layer建立连接
    glGenRenderbuffers(1, &renderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, renderBuffer);
    [self.context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer];
    
    //3.获取帧缓存区名称，绑定帧缓存区以及将渲染缓存区附着到帧缓存区上
    glGenFramebuffers(1, &frameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, frameBuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, renderBuffer);
}

//从图片中加载纹理
-(GLuint)createTextureWithImage:(UIImage *)image{
    //1.将UIImage转成CGImageRef
    CGImageRef cgimage = [image CGImage];
    if(!cgimage){
        NSLog(@"图片加载失败");
        return 0;
    }
    
    //2.读取图片大小
    GLuint width = (GLuint)CGImageGetWidth(cgimage);
    GLuint height = (GLuint)CGImageGetHeight(cgimage);
    
    //获取图片rect
    CGRect rect = CGRectMake(0, 0, width, height);
    
    //获取图片颜色空间
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    //3.获取图片字节数
    void *imageData = malloc(width*height*4);
    //4.创建上下文
    /*
     参数1：data,指向要渲染的绘制图像的内存地址
     参数2：width,bitmap的宽度，单位为像素
     参数3：height,bitmap的高度，单位为像素
     参数4：bitPerComponent,内存中像素的每个组件的位数，比如32位RGBA，就设置为8
     参数5：bytesPerRow,bitmap的没一行的内存所占的比特数
     参数6：colorSpace,bitmap上使用的颜色空间  kCGImageAlphaPremultipliedLast：RGBA
     */
    CGContextRef context = CGBitmapContextCreate(imageData, width, height, 8, width*4, colorSpace, kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    
    //将图片翻转，默认是倒置的
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1.0f, -1.0f);
    CGColorSpaceRelease(colorSpace);
    CGContextClearRect(context, rect);
    
    //对图片进行重新绘制，得到一张新的解压缩后的位图
    CGContextDrawImage(context, rect, cgimage);
    
    //设置图片纹理属性
    //5.获取纹理ID
    GLuint textureID;
    glGenTextures(1, &textureID);
    glBindTexture(GL_TEXTURE_2D, textureID);
    
    //6.载入纹理2D数据
    /*
     参数1：纹理模式，GL_TEXTURE_1D、GL_TEXTURE_2D、GL_TEXTURE_3D
     参数2：加载的层次，一般设置为0
     参数3：纹理的颜色值GL_RGBA
     参数4：宽
     参数5：高
     参数6：border，边界宽度
     参数7：format
     参数8：type
     参数9：纹理数据
     */
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, imageData);
    
    //7、设置纹理属性
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    
    //8.绑定纹理
    /*
    参数1：纹理维度
    参数2：纹理ID,因为只有一个纹理，给0就可以了。
    */
    glBindTexture(GL_TEXTURE_2D, 0);
    
    //9.释放context，imageData
    CGContextRelease(context);
    free(imageData);
    
    //10.返回纹理ID
    
    return textureID;
}


//开始一个滤镜动画
-(void)startFilterAnimation{
    //1.判断displayLink是否为空
    if(self.displayLink){
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    self.startTimeVal = 0;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(timeAction)];
    
    //将displaylink加入到runloop循环
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
//动画
-(void)timeAction{
    //displayLink 当前时间戳
    if(self.startTimeVal == 0){
        self.startTimeVal = self.displayLink.timestamp;
    }
    
    //使用program
    glUseProgram(self.program);
    //绑定buffer
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer);
    
    //传入时间
    CGFloat currentTime = self.displayLink.timestamp - self.startTimeVal;
    
    GLuint time = glGetUniformLocation(self.program, "Time");
    glUniform1f(time, currentTime);
    
    //清除画布
    glClear(GL_COLOR_BUFFER_BIT);
    glClearColor(1, 1, 1, 1);
    
    //重绘
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    //渲染
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
}

-(void)render{
    //清除画布
    glClear(GL_COLOR_BUFFER_BIT);
    glClearColor(1, 1, 1, 1);
    
    glUseProgram(self.program);
    
    glBindBuffer(GL_ARRAY_BUFFER, self.vertexBuffer);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
}


-(void)changeTitle:(UIButton *)btn{
    //1. 选择默认shader
    if (btn.tag == Tag) {
        [self setupNormalShaderProgram];
    }else if(btn.tag == Tag+1){
        [self setupSplitGrayShaderProgram];
    }else if(btn.tag == Tag+2){
        [self setupSplitReversalShaderProgram];
    }else if(btn.tag == Tag+3){
        [self setupSplitMosaicShaderProgram];
    }else if(btn.tag == Tag+4){
        [self setupSplitHexagonMosaicShaderProgram];
    }else if(btn.tag == Tag+5){
        [self setupSplitTriangleMosaicShaderProgram];
    }
    
    // 重新开始滤镜动画
    // [self startFilerAnimation];
    
    //渲染
    [self render];
}

#pragma mark - shader

//默认着色器
-(void)setupNormalShaderProgram{
    //设置着色器程序
    [self setupShaderProgramWithName:@"Normal"];
}

-(void)setupSplitGrayShaderProgram{
    [self setupShaderProgramWithName:@"Gray"];
}

-(void)setupSplitReversalShaderProgram{
    [self setupShaderProgramWithName:@"Reversal"];
}

-(void)setupSplitMosaicShaderProgram{
    [self setupShaderProgramWithName:@"Mosaic"];
}

-(void)setupSplitHexagonMosaicShaderProgram{
    [self setupShaderProgramWithName:@"HexagonMosaic"];
}

-(void)setupSplitTriangleMosaicShaderProgram{
    [self setupShaderProgramWithName:@"TriangleMosaic"];
}


//初始化着色器程序
-(void)setupShaderProgramWithName:(NSString *)name{
    //1.获取着色器program
    GLuint program = [self programWithShaderName:name];
    
    //2.使用program
    glUseProgram(program);
    //3.获取position，texture，textureCoords的索引位置
    GLuint positionSlot = glGetAttribLocation(program, "Position");
    GLuint textureSlot = glGetUniformLocation(program, "Texture");
    GLuint textureCoordSlot = glGetAttribLocation(program, "TextureCoords");

    //4.激活纹理，绑定纹理ID
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, self.textureID);
    
    //5.纹理sample
    glUniform1i(textureSlot, 0);
    
    //6.打开positionSlot属性并传递数据到positionSlot(顶点坐标)
    glEnableVertexAttribArray(positionSlot);
    glVertexAttribPointer(positionSlot, 3, GL_FLOAT, GL_FALSE, sizeof(SenceVertex), NULL+offsetof(SenceVertex, positionCoord));
    
    
    //7.打开textureCoordSlot属性并传递数据到textureCoordslot(纹理坐标)
    glEnableVertexAttribArray(textureCoordSlot);
    glVertexAttribPointer(textureCoordSlot, 2, GL_FLOAT, GL_FALSE, sizeof(SenceVertex), NULL+offsetof(SenceVertex, textureCoord));

    
    //8.保存program ，界面销毁则释放
    self.program = program;

}


#pragma mark - shader compile and link


//link shader
-(GLuint)programWithShaderName:(NSString *)shaderName{
    //1.编译顶点着色器/片源着色器
    GLuint vertexShader = [self compileShaderWithName:shaderName type:GL_VERTEX_SHADER];
    GLuint fragmentShader = [self compileShaderWithName:shaderName type:GL_FRAGMENT_SHADER];
    //2.将顶点/片元附着到program
    GLuint program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    
    //3.link
    glLinkProgram(program);
    
    //4.检查link是否成功
    GLint success;
    glGetProgramiv(program, GL_LINK_STATUS, &success);
    if(success == GL_FALSE){
        GLchar message[256];
        glGetProgramInfoLog(program, sizeof(message), 0, &message[0]);
        NSString *messageString  = [NSString stringWithUTF8String:message];
        NSAssert(NO, @"program链接失败:%@",messageString);
        return 0;
    }
    
    //5.返回program
    return program;
}

//编译shader代码

-(GLuint)compileShaderWithName:(NSString *)name type:(GLenum)shaderType{
    //1.获取shader路径
    NSString *shaderPath = [[NSBundle mainBundle]pathForResource:name ofType:shaderType == GL_VERTEX_SHADER ? @"vsh" : @"fsh"];
    NSError *error;
    NSString *shaderString = [NSString stringWithContentsOfFile:shaderPath encoding:NSUTF8StringEncoding error:&error];
    
    if(!shaderString){
        NSAssert(NO, @"读取失败");
        return 0;
    }
    
    //2.创建shader
    GLuint shader = glCreateShader(shaderType);
    
    //3.获取shader source
    const char *shaderStringUTF8 = [shaderString UTF8String];
    int shaderStringLength = (int)[shaderString length];
    glShaderSource(shader, 1, &shaderStringUTF8, &shaderStringLength);
    
    //4.编译shader
    glCompileShader(shader);
    
    //5.查看编译是否成功
    GLint success;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if(success == GL_FALSE){
        GLchar message[256];
        glGetShaderInfoLog(shader, sizeof(message), 0, &message[0]);
        NSString *messageString = [NSString stringWithUTF8String:message];
        NSAssert(NO, @"shader编译失败:%@",messageString);
        return 0;
    }
    
    //6.返回shader
    return shader;
}

//获取渲染缓存区的宽
-(GLuint)drawableWidth{
    GLint backingWidth;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    
    return backingWidth;;
}

//获取渲染缓存区的高
- (GLint)drawableHeight{
    GLint backingHeight;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    return backingHeight;
}
@end
