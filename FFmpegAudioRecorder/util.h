#ifndef UTIL_H
#define UTIL_H

#include <netinet/in.h>
#include <ifaddrs.h>

#ifndef noprintf
extern void noprintf(char *format, ...);
#endif
   
#define _DEUBG_
#ifdef _DEUBG_
	#define DBG printf
#else
	#define DBG noprintf
#endif

#define MULTICAST_ADDR "239.255.255.250"
#define MULTICAST_PORT 3702
#define NET_MAX_INTERFACE 4

#ifdef __APPLE__
#define INTERFACE_NAME_1 "en0"
#define INTERFACE_NAME_2 "en1"
#else
#define INTERFACE_NAME_1 "eth0"
#define INTERFACE_NAME_2 "eth1"
#endif
// Network

typedef enum eRTSPOperation {
    eOptions        = 0,
    eAnnounce,
    eDescribe,
    eSetup,
    ePlay,
    ePause,
    eTeardown,
    eSetParameter,
    eGetParameter,
    eRTSPOperation_Max,
}eRTSPOperation;

typedef enum eRTSPClient {
    eVLC,
    eQuickTime,
    eUNKNOW_PLAYER,
} eRTSPClient;

extern struct sockaddr_in gMSockAddr;
extern char gpLocalAddr[NET_MAX_INTERFACE][32];

extern int createMulticastClient(char *pAddress, int port);
extern int createUnicastClient(struct sockaddr_in *pSockAddr,int port);

extern int createMulticastServer(char *pAddress, int port);
extern int createUnicastServer(char *pAddress, int port);

// Xml send callback
extern char * getMyIpString(char *pInterfaceName);
extern char * initMyIpString(void);
extern char * getMyMacAddress(void);


extern void initMyRandom(char *myipaddr);
extern long our_random() ;
extern unsigned int our_random16();
extern unsigned int our_random32();
extern void UuidGen(char *uuidbuf);


extern void setMulticastFlag(int bFlag);
extern int getMulticastFlag();

extern int createRTSPServer(int vPort);

#endif

