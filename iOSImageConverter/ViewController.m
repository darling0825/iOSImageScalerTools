//
//  ViewController.m
//  iOSImageConverter
//
//  Created by gaodun on 15/11/13.
//  Copyright © 2015年 idea. All rights reserved.
//
#import "AFNetworking.h"
#import "ViewController.h"
#import "NSDictionary+Json.h"
#import "ImageTools.h"
#import "Task.h"
#import "Base64.h"

#define TINYPNG_URL @"https://api.tinypng.com/shrink"
#define TINYPNGKEY @"GdAkR5WpO0IHKIk6x5tvWz9bafYynDRw"

@interface ViewController()
- (IBAction)getSignCode:(id)sender;
@property (unsafe_unretained) IBOutlet NSTextView *logTextView;
@property (weak) IBOutlet NSTableView *taskTableView;
@property (weak) IBOutlet NSTextField *APIKeyTextField;
@property (strong,nonatomic) NSMutableArray * taskPool;
@property (strong,nonatomic) NSString * keyParameter;
@property (weak) IBOutlet NSTextField *keyTextfield;
@property (weak) IBOutlet NSButton *check1x;
@property (weak) IBOutlet NSButton *check2x;
@property (weak) IBOutlet NSButton *check3x;

@end
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.contentView.delegate = self;
    
    NSUserDefaults *userDefaultes = [NSUserDefaults standardUserDefaults];
    if ([userDefaultes stringForKey:@"KEY"]!=nil && ![[userDefaultes stringForKey:@"KEY"] isEqualToString:@""]) {
        self.keyTextfield.stringValue=[userDefaultes stringForKey:@"KEY"];
    }
    if (self.keyTextfield.stringValue == nil || [self.keyTextfield.stringValue isEqualToString:@""]) {
        self.keyTextfield.stringValue=TINYPNGKEY;
    }
    
    
    [self.logTextView insertText:@"Welcome!"];
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}
- (NSMutableArray *)taskPool
{
    if (!_taskPool ) {
        _taskPool  = [[NSMutableArray alloc]init];
    }
    return _taskPool ;
}
-(void)dragDropViewFileList:(NSArray*)fileList
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self handleFiles:fileList];
    });
}
-(void)handleFiles:(NSArray*)fileList
{
    
    for (int i = 0 ; i < fileList.count; i ++) {
        NSString * filePath = fileList[i];
        NSArray<NSString *> * arr = [filePath componentsSeparatedByString:@"/"];
        NSMutableString * address = [[NSMutableString alloc]init];
        for (int i = 0 ; i < arr.count - 1; i++) {
            [address appendFormat:@"%@/",arr[i]];
        }
        NSString *fileName = [[[arr lastObject] componentsSeparatedByString:@"."]firstObject];
        NSString * type = [[filePath componentsSeparatedByString:@"."] lastObject];
        type = [type lowercaseString];
        
        if ((![type isEqualToString:@"png"]) && (![type isEqualToString:@"jpg"])) {
            NSLog(@"该文件不是图片类型");
            continue;
        }
        
        Task * task = [[Task alloc]init];
        task.fileName = fileName;
        task.Status = TaskStatusWait;
        task.originalURL = fileList[i];
        task.output = address;
        task.type = type;
        [self.taskPool addObject:task];
    }

    [self taskSchedul];

    [self uploadPng:self.taskPool[0]];

}
#pragma mark -- tableview delegate
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.taskPool.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    Task *job=self.taskPool[row];
    NSString * identifier=    [tableColumn identifier];
    if (identifier.intValue==0) {
        return job.fileName;
    }
    else if (identifier.intValue==1)
    {
        if (job.Status & TaskStatusWait) {
            return @"等待中";
        }
        if (job.Status & TaskStatusDoing) {
            return @"上传中";
        }
        if (job.Status & TaskStatusComplete) {
            return @"下载完成";
        }
        return @"下载错误";
    }
    return @"未知";
}
- (IBAction)getSignCode:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.tinypng.com/developers"]];
}
- (NSString *)keyParameter
{
    NSString *apikey=[NSString stringWithFormat:@"api:%@",self.keyTextfield.stringValue];
    NSString *base64=[apikey base64EncodedString];
    _keyParameter=[NSString stringWithFormat:@"Basic %@",base64];
    return _keyParameter ;
}
#pragma mark -- 任务调度
- (void)taskSchedul
{
    dispatch_async(dispatch_get_main_queue(), ^{

        NSInteger doingCount;
        NSInteger maxWorks = 2;
        doingCount = maxWorks;
        //检索正在工作的任务
        for (int i = 0; i < self.taskPool.count ;i ++)
        {
            Task * task = self.taskPool[i];
            if (task.Status == TaskStatusDoing) {
                doingCount --;
                if (doingCount == 0) {
                    break;
                }
            }
        }
        for (int i = 0 ; i < self.taskPool.count;  i++) {
            Task * task = self.taskPool[i];
            if (task.Status == TaskStatusWait) {
                task.Status = TaskStatusDoing;
                [self uploadPng:task];
                doingCount --;
                if (doingCount == 0) {
                    break;
                }
            }
        }
        
        [self.taskTableView reloadData];
        
    });
}
#pragma mark -- 图片处理
-(void)uploadPng:(Task *)job
{
    NSData *pngData=[NSData dataWithContentsOfFile:job.originalURL];
    if (pngData==nil) {
        return;
    }
    
    NSMutableURLRequest *request=[[NSMutableURLRequest alloc]initWithURL:[NSURL URLWithString:TINYPNG_URL]];
    [request addValue:self.keyParameter forHTTPHeaderField:@"Authorization"];
    request.HTTPMethod=@"POST";
    [request addValue:@"image/png" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:pngData];

    AFHTTPRequestOperation *op=[[AFHTTPRequestOperationManager manager] HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"POST SUCCESS RESPONSE:\n%@",responseObject);
        NSDictionary *jsonResponse=(NSDictionary *)responseObject;
        NSDictionary *output=[jsonResponse objectForKey:@"output"];
        job.remoteURL = [output objectForKey:@"url"];
        job.width = [[output objectForKey:@"width"] floatValue];
        job.height = [[output objectForKey:@"height"] floatValue];
        job.compressRatio = [[output objectForKey:@"ratio"] floatValue];
        NSLog(@"%zd%zd%zd",self.check1x.state ,self.check2x.state ,self.check3x.state);
        if (self.check1x.state ) {
            [self downloadImage:job type:Download1x];
        }
        if (self.check2x.state ) {
            [self downloadImage:job type:Download2x];
        }
        if (self.check3x.state ) {
            [self downloadImage:job type:Download3x];
        }
        [self taskSchedul];

    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"出错了");
    }];
    
    [[AFHTTPRequestOperationManager manager].operationQueue addOperation:op];
    
}
-(void)downloadImage:(Task *)job type:(ImageType)type
{
    NSMutableURLRequest *downloadRequest=[[NSMutableURLRequest alloc]initWithURL:[NSURL URLWithString:job.remoteURL]];
    [downloadRequest addValue:self.keyParameter forHTTPHeaderField:@"Authorization"];
    [downloadRequest addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [downloadRequest setHTTPMethod:@"POST"];
    if (type == Download1x) {
        NSDictionary * params = @{@"resize": @{
            @"method": @"fit",
            @"width": @(job.width / 3 ),
            @"height": @(job.height / 3)
            }};
        [downloadRequest setHTTPBody:[params jsonData]];
    }
    if (type == Download2x) {
        NSDictionary * params = @{@"resize": @{
              @"method": @"fit",
              @"width": @(job.width / 3 * 2),
              @"height": @(job.height / 3 * 2)
              }};
        [downloadRequest setHTTPBody:[params jsonData]];
    }
    
    AFHTTPRequestOperation *requestOperation = [[AFHTTPRequestOperation alloc] initWithRequest:downloadRequest];
    [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSMutableString * address = [NSMutableString stringWithString:job.output];
        [address appendString:@"iOSImageConverter"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager createDirectoryAtPath:address attributes:nil];
        NSData *newFileData=(NSData *)responseObject;
        NSDictionary * nxDic = @{[@(Download1x) stringValue]:@"",
                                 [@(Download2x) stringValue]:@"@2x",
                                 [@(Download3x) stringValue]:@"@3x"};
        [newFileData writeToFile:[NSString stringWithFormat:@"%@/%@%@.%@",address,job.fileName,nxDic[[@(type) stringValue]],job.type] atomically:YES];
        [self taskSchedul];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        
    }];
    
    [[AFHTTPRequestOperationManager manager].operationQueue addOperation:requestOperation];
}
@end
