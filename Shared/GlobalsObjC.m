
void DLog(NSString *format, ...)
{
#ifndef DEBUG
	if(Settings.logActivityToConsole)
	{
#endif
		va_list args;
		va_start(args, format);
		NSLogv(format, args);
		va_end(args);
#ifndef DEBUG
	}
#endif
}

API *api;
NSString *currentAppVersion;
NSArray *kPullRequestSectionNames;
