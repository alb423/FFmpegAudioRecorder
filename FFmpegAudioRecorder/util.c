#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <net/if.h>
#include <netdb.h>
#include <arpa/inet.h>

#include <ifaddrs.h>

#include "util.h"

char gpLocalAddr[NET_MAX_INTERFACE][32]={{0}};
char gpMacAddr[NET_MAX_INTERFACE][32]={{0}};
#define LOCAL_ADDR gpLocalAddr//"192.168.2.102"

static int _gIsMulticast = 0;

struct sockaddr_in gMSockAddr;

char * CopyString(char *pSrc)
{
    int vLen = 0;
    char *pDst = NULL;
    
    if(!pSrc) return NULL;
    
    vLen = strlen(pSrc);
    pDst = malloc(vLen+1);
    memset(pDst, 0, vLen+1);
    memcpy(pDst, pSrc, vLen);
    
    return pDst;
}

void setMulticastFlag(int bFlag)
{
   _gIsMulticast = bFlag;
}

int getMulticastFlag()
{
   return _gIsMulticast;
}

char * getMyMacAddress(void)
{
    return NULL;//CopyString(gpMacAddr[0]);
}

// Utilities of Network
char * getMyIpString(char *pIfName)
{
   int i = 0;
   if(pIfName==NULL)
   return NULL;
   
   for(i=0;i<NET_MAX_INTERFACE;i++)
   {
      if(strncmp("en1", pIfName, 3)==0)
      {
         return CopyString(gpLocalAddr[1]);
      } 
   }
   return CopyString(gpLocalAddr[0]);
}


char * initMyIpString(void)
{
   int vInterfaceCount=0;
   char pInterface[128]={0};
   struct ifaddrs * ifAddrStruct=NULL;
   struct ifaddrs * ifa=NULL;
   void * tmpAddrPtr=NULL;
   
   getifaddrs(&ifAddrStruct);
   
   for (ifa = ifAddrStruct; ifa != NULL; ifa = ifa->ifa_next) 
   {
      if (ifa ->ifa_addr->sa_family==AF_INET) 
      {   
         // check it is IP4
         // is a valid IP4 Address
         char addressBuffer[INET_ADDRSTRLEN];
         tmpAddrPtr=&((struct sockaddr_in *)ifa->ifa_addr)->sin_addr;
         
         inet_ntop(AF_INET, tmpAddrPtr, addressBuffer, INET_ADDRSTRLEN);
         //DBG("%s IP Address %s\n", ifa->ifa_name, addressBuffer); 
         if(strncmp(ifa->ifa_name, INTERFACE_NAME_1, 2)==0)
         {
            // Note: you may set local address for different interface. For example:eth0, eth1
            memcpy(gpLocalAddr[vInterfaceCount], addressBuffer, strlen(addressBuffer));
            memset(pInterface, 0 ,128);
            memcpy(pInterface, ifa->ifa_name, strlen(ifa->ifa_name));
            
            #ifdef __APPLE__
               // I don't know how to get Mac Address in Mac OS
               sprintf(gpMacAddr[0], "10ddb1acc6ee");
               sprintf(gpMacAddr[1], "4c8d79eaee74");
            #else            
            {
               // For linux system
               int sock;
               struct ifreq ifr;
               
               sock = socket(AF_INET, SOCK_DGRAM, 0);
               ifr.ifr_addr.sa_family = AF_INET;
               
               strncpy(ifr.ifr_name, pInterface, IFNAMSIZ-1);
               
               ioctl(sock, SIOCGIFHWADDR, &ifr);
               
               close(sock);
               
               sprintf(gpMacAddr[vInterfaceCount], "%.2x%.2x%.2x%.2x%.2x%.2x", 
               (unsigned char)ifr.ifr_hwaddr.sa_data[0],
               (unsigned char)ifr.ifr_hwaddr.sa_data[1],
               (unsigned char)ifr.ifr_hwaddr.sa_data[2],
               (unsigned char)ifr.ifr_hwaddr.sa_data[3],
               (unsigned char)ifr.ifr_hwaddr.sa_data[4],
               (unsigned char)ifr.ifr_hwaddr.sa_data[5]);
               //DBG("MAC %s\n", gpMacAddr[vInterfaceCount]); 
            }
            #endif
            vInterfaceCount++;
         } 
      } 
      else if (ifa->ifa_addr->sa_family==AF_INET6) 
      {   
         // check it is IP6
         // is a valid IP6 Address
         tmpAddrPtr=&((struct sockaddr_in6 *)ifa->ifa_addr)->sin6_addr;
         char addressBuffer[INET6_ADDRSTRLEN];
         inet_ntop(AF_INET6, tmpAddrPtr, addressBuffer, INET6_ADDRSTRLEN);
         //DBG("%s IP Address %s\n", ifa->ifa_name, addressBuffer); 
      }         
   }
   
   
   DBG("gpLocalAddr is set to %s, MAC is %s\n\n", gpLocalAddr[0], gpMacAddr[0]);    
   if (ifAddrStruct!=NULL) freeifaddrs(ifAddrStruct);
   return gpLocalAddr[0];
}

int createUnicastClient(struct sockaddr_in *pSockAddr, int port)
{
   // http://www.tenouk.com/Module41c.html
   int sd=-1;
   
   struct timeval timeout;
   timeout.tv_sec  = 10;
   timeout.tv_usec = 0;
   
   sd = socket(AF_INET, SOCK_DGRAM, 0);
   if(sd < 0)
   {
      perror("Opening datagram socket error");
      exit(1);
   }
   else
      DBG("Opening the datagram socket %d...OK.\n", sd);
   
   if(setsockopt(sd, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout)) < 0)
   {
      DBG("setsockopt...error.\n");
   }
   
#if 0
   int reuse=1;
   struct sockaddr_in localSock;   
   if(setsockopt(sd, SOL_SOCKET, SO_REUSEADDR, (char *)&reuse, sizeof(reuse)) < 0)
   {
      perror("Setting SO_REUSEADDR error");
      close(sd);
      exit(1);
   }
   else
      DBG("Setting SO_REUSEADDR...OK.\n");
         
   // The host may have many interface
   // If needed, we may create the socket to bind the interface that data was sent.
   localSock.sin_family = AF_INET;
   localSock.sin_port = htons(MULTICAST_PORT);
   //localSock.sin_addr.s_addr = htonl(INADDR_ANY);
   localSock.sin_addr.s_addr = inet_addr(gpLocalAddr[0]);
   if(bind(sd, (struct sockaddr*)&localSock, sizeof(localSock)))
   {
      perror("Binding datagram socket error");
      close(sd);
      exit(1);
   }
   else
      DBG("Binding port:%d socket...OK.\n",port);
#endif
   
   return sd;
}


int createMulticastClient(char *pAddress, int port)
{
   // http://www.tenouk.com/Module41c.html
   struct in_addr localInterface;
   int i, sd=-1;
   
   struct ip_mreq group;
   struct timeval timeout;
   timeout.tv_sec  = 10;
   timeout.tv_usec = 0;
   
   if(!pAddress)
      return -1;
   if(strlen(pAddress)==0)
      return -1;
   
   sd = socket(AF_INET, SOCK_DGRAM, 0);
   if(sd < 0)
   {
      perror("Opening datagram socket error");
      exit(1);
   }
   else
      DBG("Opening multicast client socket %d for ip %s...OK.\n", sd, pAddress);
   
   if(setsockopt(sd, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout)) < 0)
   {
      DBG("setsockopt...error.\n");
   }

    int reuse=1;
    if(setsockopt(sd, SOL_SOCKET, SO_REUSEADDR, (char *)&reuse, sizeof(reuse)) < 0)
    {
        perror("Setting SO_REUSEADDR error");
        close(sd);
        exit(1);
    }
    else
        DBG("Setting SO_REUSEADDR...OK.\n");
   
    if(setsockopt(sd, SOL_SOCKET, SO_REUSEPORT, (char *)&reuse, sizeof(reuse)) < 0)
    {
        perror("Setting SO_REUSEADDR error");
        close(sd);
        exit(1);
    }
    else
        DBG("Setting SO_REUSEADDR...OK.\n");
    
   unsigned char ttl, loop;
   int ttlSize, loopSize;
   loop = 1;/*0;*/ loopSize = sizeof(loop);
   ttl = 5; ttlSize = sizeof(ttl);
   setsockopt(sd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, loopSize);
   setsockopt(sd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, ttlSize);
   getsockopt(sd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, (socklen_t *)&loopSize);
   getsockopt(sd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, (socklen_t *)&ttlSize);
   
   memset((char *) &gMSockAddr, 0, sizeof(gMSockAddr));
   gMSockAddr.sin_family = AF_INET;
   gMSockAddr.sin_addr.s_addr = inet_addr(MULTICAST_ADDR);
   gMSockAddr.sin_port = htons(port);
   
   localInterface.s_addr = inet_addr(pAddress);
   
   if(setsockopt(sd, IPPROTO_IP, IP_MULTICAST_IF, (char *)&localInterface.s_addr, sizeof(localInterface)) < 0)
   {
      perror("Setting local interface error");
   }
   else
      DBG("Setting the local interface...OK\n");    
   

   for(i=0;i<NET_MAX_INTERFACE;i++)
   {
      group.imr_multiaddr.s_addr = inet_addr(pAddress);
      if(strlen(gpLocalAddr[i])!=0)
      {
         group.imr_interface.s_addr = inet_addr(gpLocalAddr[i]);
         // In MAC, if we set INADDR_ANY, it will set only the 1st network interface
         // group.imr_interface.s_addr = INADDR_ANY;
         if(setsockopt(sd, IPPROTO_IP, IP_ADD_MEMBERSHIP, (char *)&group, sizeof(group)) < 0)
         {
            perror("setsockopt IP_ADD_MEMBERSHIP error");
            // This error may happened if some process had already do IP_ADD_MEMBERSHIP
            // This error can be omited
            //close(sd);
            //exit(1);
         }
         else
         {
            DBG("setsockopt IP_ADD_MEMBERSHIP for %s ...OK.\n", gpLocalAddr[i]);
         }
      }
   }
   
   
   return sd;
}

int createMulticastServer(char *pAddress, int port)
{
   struct ip_mreq group;
   struct sockaddr_in localSock;
   int i, sd;
   int reuse = 1;
   
   sd = socket(AF_INET, SOCK_DGRAM, 0);

   if(sd < 0)
   {
      perror("Opening datagram socket error");
      exit(1);
   }
   else
      DBG("Opening multicast server socket %d for ip %s...OK.\n",sd, pAddress);
   

   if(setsockopt(sd, SOL_SOCKET, SO_REUSEADDR, (char *)&reuse, sizeof(reuse)) < 0)
   {
      perror("Setting SO_REUSEADDR error");
      close(sd);
      exit(1);
   }
   else
      DBG("Setting SO_REUSEADDR...OK.\n");

   
   memset((char *) &localSock, 0, sizeof(localSock));
   localSock.sin_family = AF_INET;
   localSock.sin_port = htons(port);
   localSock.sin_addr.s_addr = INADDR_ANY;
   
   int opt = 1;
   if(setsockopt(sd, IPPROTO_IP, IP_PKTINFO, &opt, sizeof(opt)) < 0)
      printf("set IP_PKTINFO error\n");
       
   for(i=0;i<NET_MAX_INTERFACE;i++)
   {
      group.imr_multiaddr.s_addr = inet_addr(pAddress);
      if(strlen(gpLocalAddr[i])!=0)
      {
         group.imr_interface.s_addr = inet_addr(gpLocalAddr[i]); 
         // In MAC, if we set INADDR_ANY, it will set only the 1st network interface
         // group.imr_interface.s_addr = INADDR_ANY;
         if(setsockopt(sd, IPPROTO_IP, IP_ADD_MEMBERSHIP, (char *)&group, sizeof(group)) < 0)
         {
            perror("setsockopt IP_ADD_MEMBERSHIP error");
            // This error may happened if some process had already do IP_ADD_MEMBERSHIP
            // This error can be omited
            //close(sd);
            //exit(1);
         }
         else
         {
            DBG("setsockopt IP_ADD_MEMBERSHIP for %s ...OK.\n", gpLocalAddr[i]);
         }
      }
   }
               
   if(bind(sd, (struct sockaddr*)&localSock, sizeof(localSock)))
   {
      perror("Binding datagram socket error");
      close(sd);
      exit(1);
   }
   else
      DBG("Binding port:%d socket...OK.\n",port);
   
   return sd;
}


int createUnicastServer(char *pAddress, int vPort)
{
   int sd;
   struct sockaddr_in localSock;   
   
   if(!pAddress)
      return -1;
   if(strlen(pAddress)==0)
      return -1;
         
   sd = socket(AF_INET, SOCK_DGRAM, 0);
   if(sd < 0)
   {
      perror("Opening datagram socket error");
      exit(1);
   }
   else
      DBG("Opening unicast server socket %d for ip %s...OK.\n",sd, pAddress);
   
   {
      int reuse = 1;
      if(setsockopt(sd, SOL_SOCKET, SO_REUSEADDR, (char *)&reuse, sizeof(reuse)) < 0)
      {
         perror("Setting SO_REUSEADDR error");
         close(sd);
         exit(1);
      }
      else
         DBG("Setting SO_REUSEADDR...OK.\n");
   }
   
   memset((char *) &localSock, 0, sizeof(localSock));
   localSock.sin_family = AF_INET;
   localSock.sin_port = htons(vPort);
   localSock.sin_addr.s_addr = inet_addr(pAddress);
   
   if(bind(sd, (struct sockaddr*)&localSock, sizeof(localSock)))
   {
      perror("Binding datagram socket error");
      close(sd);
      exit(1);
   }
   else
      DBG("Binding datagram socket...OK.\n");
   
   return sd;
}


       
// Random function
void initMyRandom(char *myipaddr)
{
   unsigned int ourAddress;
   struct timeval timeNow;
   
   ourAddress = ntohl(inet_addr(myipaddr));
   gettimeofday(&timeNow, NULL);
   
   unsigned int seed = ourAddress^timeNow.tv_sec^timeNow.tv_usec;
     
   srandom(seed);
}

long our_random() 
{
   return random();
}

unsigned int our_random16()
{
   long random1 = our_random();
   return (unsigned int)(random1&0xffff);
}


unsigned int our_random32() 
{  
   long random1 = our_random();
   long random2 = our_random();
   
   return (unsigned int)((random2<<31) | random1);
}
              
void UuidGen(char *uuidbuf)
{
   sprintf(uuidbuf, "%08x-%04x-%04x-%04x-%08x%04x",our_random32(), our_random16(),our_random16(),our_random16(),our_random32(), our_random16());    
}     


void noprintf(char *format, ...)
{
   ;
}




#pragma mark - a simple RTSP Server

#ifndef UINT_MAX
#define UINT_MAX 0xFFFFU/0xFFFFFFFFUL
#endif

typedef struct
{
    /**//* byte 0 */
    unsigned char csrc_len:4;
    unsigned char extension:1;
    unsigned char padding:1;
    unsigned char version:2;
    /**//* byte 1 */
    unsigned char payload:7;
    unsigned char marker:1;
    /**//* bytes 2, 3 */
    unsigned short seq_no;
    /**//* bytes 4-7 */
    unsigned long timestamp;
    /**//* bytes 8-11 */
    unsigned long ssrc;
}/*__attribute__((aligned(4)))*/ RTP_FIXED_HEADER;

typedef struct
{
	struct
	{
		int fd;
		struct sockaddr_in in,to;
	} rtp, rtcp;
	
	RTP_FIXED_HEADER	rtp_hdr;
	int octetCount;
	int packetCount;
} RTP_SESSION;

RTP_SESSION audio_rtp;
eRTSPClient veClientPlayer;
int bIsRTPOverTCP, bIsRTPOverHTTP;
int CSeq_no;
int audio_port;
char pClientIpAddress[32], pServerIpAddress[32];



const char DeBase64Tab[] =
{
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    62,        // '+'
    0, 0, 0,
    63,        // '/'
    52, 53, 54, 55, 56, 57, 58, 59, 60, 61,        // '0'-'9'
    0, 0, 0, 0, 0, 0, 0,
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
    13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,        // 'A'-'Z'
    0, 0, 0, 0, 0, 0,
    26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
    39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51,        // 'a'-'z'
};


int base64_decode(const char* pSrc, unsigned char* pDst, int nSrcLen)
{
    int nDstLen;
    int nValue;
    int i;
    
    i = 0;
    nDstLen = 0;
    
    while (i < nSrcLen)
    {
        if (*pSrc != '\r' && *pSrc!='\n')
        {
            nValue = DeBase64Tab[*pSrc++] << 18;
            nValue += DeBase64Tab[*pSrc++] << 12;
            *pDst++ = (nValue & 0x00ff0000) >> 16;
            nDstLen++;
            
            if (*pSrc != '=')
            {
                nValue += DeBase64Tab[*pSrc++] << 6;
                *pDst++ = (nValue & 0x0000ff00) >> 8;
                nDstLen++;
                
                if (*pSrc != '=')
                {
                    nValue += DeBase64Tab[*pSrc++];
                    *pDst++ =nValue & 0x000000ff;
                    nDstLen++;
                }
            }
            
            i += 4;
        }
        else
        {
            pSrc++;
            i++;
        }
    }
    
    *pDst = '\0';
    
    return nDstLen;
}

char *base64_encode(char *out, int out_size, const unsigned char *in, int in_size)
{
    static const char b64[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    char *ret, *dst;
    unsigned i_bits = 0;
    int i_shift = 0;
    int bytes_remaining = in_size;
    
    if (in_size >= UINT_MAX / 4 ||
        out_size < (in_size+2) / 3 * 4 + 1)
        return NULL;
    ret = dst = out;
    while (bytes_remaining) {
        i_bits = (i_bits << 8) + *in++;
        bytes_remaining--;
        i_shift += 8;
        
        do {
            *dst++ = b64[(i_bits << 6 >> i_shift) & 0x3f];
            i_shift -= 6;
        } while (i_shift > 6 || (bytes_remaining == 0 && i_shift > 0));
    }
    while ((dst - ret) & 3)
        *dst++ = '=';
    *dst = '\0';
    
    return ret;
}

void GetPresentTime(char *pTimeBuf)
{
	char *wmon[]={"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
	char *nweek[]={"Sun", "Mon","Tue","Wed","Thu","Fri","Sat"};
	//char timeBuf[36];
	time_t timep;
	struct tm *p;
	
	time(&timep);
	p=localtime(&timep);
	
	sprintf(pTimeBuf, "%s, %s %02d %d %02d:%02d:%02d GMT", nweek[p->tm_wday], wmon[p->tm_mon], (p->tm_mday),
            (1900+p->tm_year), (p->tm_hour), (p->tm_min), (p->tm_sec) );
	
}

int rtspParser(char *Buf, char *cfBuff)
{
    int veRTSPOperation;
	int i;
	char *pget=NULL;
	char *para_buf, msg_buf[128];
	
	CSeq_no = 0;
	veRTSPOperation = 0;
	
	para_buf = Buf;
	
	
	do{
        
		if(bIsRTPOverTCP)
		{
			//把 RTP over TCP 的起始符號抓出來
			if( (strlen(para_buf) == 1) && ((pget=strstr(para_buf, "$")) != NULL) )//找出對應碼
			{
				bIsRTPOverTCP = 1;
			}
		}
		
		if( bIsRTPOverHTTP == 0 ) {
			if( (pget=strstr(para_buf, "HTTP/1.0")) != NULL)
			{
				if( strncmp( para_buf, "GET ", 4) == 0 ) {
					bIsRTPOverHTTP = 1;
                    
                    // add http header when response
                    /*
                     case RTPoverHTTP:
                     sprintf(response, "HTTP/1.0 200 OK\r\nServer: DSS/5.5.5 (Build/489.16; Platform/Linux; Release/Darwin; state/beta; )\r\nContent-Type: application/x-rtsp-tunnelled\r\n\r\n");
                     
                     if(isRTPOverTCP)
                     pthread_mutex_lock(&orstp_mutex);
                     send(connfd, response, strlen(response),0);
                     //write(connfd, response, strlen(response));
                     if(isRTPOverTCP)
                     pthread_mutex_unlock(&orstp_mutex);
                     break;
                     */
                    
					fprintf(stderr, "\nisRTPOverHTTP\n");
				}
                
				break;
			}
		}
        
		memset(msg_buf, '\0', sizeof(msg_buf));
		if( (pget=strstr(para_buf, "OPTIONS")) != NULL)//找出對應碼
		{
			veRTSPOperation = eOptions;
		}
		else if( (pget=strstr(para_buf, "ANNOUNCE")) != NULL)
		{
			veRTSPOperation = eAnnounce;
		}
		else if( (pget=strstr(para_buf, "DESCRIBE")) != NULL)//找出對應碼
		{
			//time( &TimeMulticastStart );
			veRTSPOperation = eDescribe;
			if( (pget=strstr(para_buf, "User-Agent:")) != NULL)
			{
				sscanf(pget, "User-Agent:%*[ :]%[^\r\n]", msg_buf );
				memcpy(cfBuff, msg_buf, strlen(msg_buf) );//將 User agent 訊息丟至 SDP 的 Tool 中
                
				if( (pget=strstr(msg_buf, "VLC")) != NULL)
					veClientPlayer = eVLC;
				else if( (pget=strstr(msg_buf, "QuickTime")) != NULL){
					veClientPlayer = eQuickTime;
				}
				else
					veClientPlayer = eUNKNOW_PLAYER;
			}
		}
		else if( (pget=strstr(para_buf, "SETUP")) != NULL)//找出對應碼
		{
			veRTSPOperation = eSetup;
            
            // support "port" for multicast, add by albert
            if( (pget=strstr(para_buf, "port=")) != NULL)
			{
                sscanf( pget, "port=%d", &audio_port );
                audio_rtp.rtp.in.sin_family = AF_INET;
                audio_rtp.rtp.in.sin_port = htons(audio_port);
                audio_rtp.rtp.in.sin_addr.s_addr = inet_addr (pClientIpAddress);
			}
			else if( (pget=strstr(para_buf, "client_port=")) != NULL)
			{
                sscanf( pget, "client_port=%d", &audio_port );
                audio_rtp.rtp.in.sin_family = AF_INET;
                audio_rtp.rtp.in.sin_port = htons(audio_port);
                audio_rtp.rtp.in.sin_addr.s_addr = inet_addr (pClientIpAddress);
			}
            
            // 20120928 albert.liao modified start
			if( (pget=strstr(para_buf, "RTP/AVP/TCP")) != NULL)
			{
				//fprintf(stderr, "++++++++ RTP/AVP/TCP ++++++++++\n");
                
				bIsRTPOverTCP = 1;
                
				if( (pget=strstr(para_buf, "interleaved=")) != NULL)
				{
					int num1, num2;
					sscanf( pget, "interleaved=%d-%d", &num1, &num2);
                    // TODO
				}
                else
                {
                    
                }
			}
		}
		else if( (pget=strstr(para_buf, "PLAY")) != NULL)//找出對應碼
		{
			veRTSPOperation = ePlay;
		}
		else if( (pget=strstr(para_buf, "PAUSE")) != NULL)//找出對應碼
		{
			veRTSPOperation = ePause;
		}
		else if( (pget=strstr(para_buf, "TEARDOWN")) != NULL)//找出對應碼
		{
			veRTSPOperation = eTeardown;
		}
		else if( (pget=strstr(para_buf, "SET_PARAMETER")) != NULL)//找出對應碼
		{
			veRTSPOperation = eSetParameter;
		}
		else if( (pget=strstr(para_buf, "GET_PARAMETER")) != NULL)//找出對應碼
		{
			veRTSPOperation = eGetParameter;
		}
	}while(0);
	
	
	if( (pget=strstr(para_buf, "CSeq:")) != NULL)//找出對應碼
	{
		sscanf( pget, "CSeq:%d", &CSeq_no);
	}
	
	
	for(i=0;i<strlen(Buf);i++)
	{
		if(Buf[i]=='\r' && Buf[i+1]=='\n'&&Buf[i+2]=='\r' && Buf[i+3]=='\n')
		{
			//printf("Get Command:\n");
			return 0;
		}
	}
	return veRTSPOperation;
}

int sendRTPData( RTP_SESSION *rtp, char *data, size_t size )
{
	char buff[1500];
    
	if( ( size == 0 ) ||
       ( size > (1500 - sizeof(RTP_FIXED_HEADER)) ) ||
       ( rtp == NULL ) ||
       (data == NULL) ) {
		return -1;	// 參數錯誤
	}
    
	memcpy( buff, &rtp->rtp_hdr, sizeof(RTP_FIXED_HEADER) );
	memcpy( &buff[sizeof(RTP_FIXED_HEADER)], data, size);
	
	return sendto( rtp->rtp.fd, buff, size+sizeof(RTP_FIXED_HEADER), 0, (struct sockaddr *)&rtp->rtp.in, sizeof (struct sockaddr_in));
	
}

void sighup(int dummy)
{
    // release resources
    perror("!!sighup\n");
	exit(1);
}

int createRTSPServer(int vPort)
{
    pid_t vProcessID=0;
    int vSocket, vConnfd, vRecvLen;
    int bReuseFlag = 1;
    char pBuffer[1024], pTmpBuffer[1024], pResponse[1024];
    char pUserAgent[512], pCurrentTimeStr[64];
	struct sockaddr_in vxServerAddr, vxClientAddr;

    signal(SIGKILL, sighup);
    
	vSocket = socket(AF_INET, SOCK_STREAM, 0);
	if( vSocket < 0)
    {
		perror("!!socket() error\n");
	}
    
	if( setsockopt(vSocket, SOL_SOCKET, SO_REUSEADDR, (const char*)&bReuseFlag, sizeof(bReuseFlag)) < 0 )
	{
		perror("!!setsockopt() error\n");
		close(vSocket);
		exit (1);
	}
    

    initMyIpString();
    char *pTmp =  getMyIpString("en0");
    memset(pServerIpAddress, 0, sizeof(pServerIpAddress));
    memcpy(pServerIpAddress, pTmp, strlen(pTmp));
    
    
    memset(&vxServerAddr, 0, sizeof(vxServerAddr));
	vxServerAddr.sin_family= AF_INET;
	vxServerAddr.sin_port= htons(vPort);
    vxServerAddr.sin_addr.s_addr = inet_addr(pServerIpAddress);
    
	if( bind(vSocket, (struct sockaddr *)&vxServerAddr, sizeof(vxServerAddr)) == -1)
    {
		perror("!!bind() error\n");
        fprintf(stderr,"error address:%s, port:%d\n",pServerIpAddress, vPort);
	}
    else
    {
        fprintf(stderr, "server is bind to %s:%d\n", pServerIpAddress, vPort);
    }
    
	if(listen(vSocket,5) == -1){
		printf("Error: listen()\n");
	}
    
    // For simplicity, I don't fork process.
    // Support only 1 client
	while(1)
	{
		socklen_t clnlen;
		clnlen= sizeof(vxClientAddr);

		//fprintf(stderr, "[%d]ACCEPT WAIT!\n",getpid());
        
        memset(&vxClientAddr, 0, sizeof(vxClientAddr));
		vConnfd= accept(vSocket,(struct sockaddr *)&vxClientAddr, &clnlen);
		if(vConnfd < 0)
		{
			perror("accept error");
			close(vSocket);
            exit(1);
        }
        else
        {
            char *pTmp;
            
            memset(pClientIpAddress, 0, sizeof(pClientIpAddress));
            pTmp = inet_ntoa(vxClientAddr.sin_addr);
            memcpy(pClientIpAddress, pTmp, strlen(pTmp));
            fprintf(stderr, "peer address is %s\n", pTmp);
        }
        audio_rtp.rtp.fd = vSocket;
        
//		vProcessID = fork();// Parent process, PID == 0
//		if (vProcessID > 0)
//		{
//			close(vConnfd);
//			usleep(100000);//avoid continue connection
//			perror("Parent Close the socket, Wait for another client\n");
//			continue;
//		}
        
        // Handle RTSP command here
		while(1)
		{
            int vSendLen=0;
            eRTSPOperation veOperation=eOptions;
            
            fd_set sets;
            struct timeval tv;
            
            tv.tv_sec=5;
            tv.tv_usec=500000;
            
            FD_ZERO(&sets);
            FD_SET(vConnfd, &sets);
            
            if( select(vConnfd+1, &sets, NULL, NULL,&tv) <= 0 )
            {
                fprintf(stderr, "select() timeout\n");
                continue;
            }

            
            memset(pTmpBuffer, 0, sizeof(pTmpBuffer));
			vRecvLen = recv(vConnfd, pTmpBuffer, sizeof(pTmpBuffer),0);
            if(vRecvLen > 0)
            {
				pTmpBuffer[vRecvLen] = 0x0;
                fprintf(stderr,"[%d] len:%d \n%s\n", vProcessID, vRecvLen, pTmpBuffer);
				if( strncmp( pBuffer, "POST ", 5) == 0 )
				{
					printf("get POST methomd\n");
					vRecvLen = read(vConnfd, pTmpBuffer, sizeof(pTmpBuffer));
					pTmpBuffer[vRecvLen] = '\0';
					base64_decode(pTmpBuffer, (unsigned char *)pBuffer, vRecvLen);
					printf("%s",pBuffer);
				}
				else
				{
					if( bIsRTPOverHTTP )
					{
                        printf("bIsRTPOverHTTP\n");
						base64_decode(pTmpBuffer,(unsigned char *)pBuffer, vRecvLen);
						printf("%s",pBuffer);
					}
					else
					{
						memcpy(pBuffer,pTmpBuffer,vRecvLen);
					}
				}
                
				memset(pUserAgent, '\0', sizeof(pUserAgent));
				veOperation = rtspParser(pBuffer, pUserAgent);
                
                GetPresentTime(pCurrentTimeStr);

                memset(pResponse, 0, sizeof(pResponse));
                switch (veOperation)
                {
                    case eOptions:
                        fprintf(stderr, "eOptions\n");
						sprintf(pResponse,
                                "RTSP/1.0 200 OK\r\nCSeq: %d\r\n"
                                "Date: %s\r\n"
                                "Public: OPTIONS, DESCRIBE, SETUP, TEARDOWN, PLAY, GET_PARAMETER, SET_PARAMETER\r\n\r\n",
                                CSeq_no, pCurrentTimeStr);
                        break;
                        
                    case eDescribe:
                    {
                        char pSDP[1024];
                        fprintf(stderr, "eDescribe\n");
                        
                        memset(pSDP, 0 , sizeof(pSDP));
						sprintf(pSDP,
                                "v=0"
                                "o=- 1073741875599202 1 IN IP4 225.0.0.1"
                                "s=Unnamed"
                                "i=RTSP Test For AAC"
                                "c=IN IP4 225.0.0.1/127"
                                "t=0 0"
                                "a=tool:LIVE555 Streaming Media v2012.04.04"
                                "a=type:broadcast"
                                "a=control:*"
                                "a=range:npt=0-"
                                "a=x-qt-text-nam:IP camera Live streaming"
                                "a=x-qt-text-inf:stream2"
                                "a=control:*"
                                "m=audio 51234 RTP/AVP 96"
                                "b=AS:64"
                                "a=x-bufferdelay:0.55000"
                                "a=rtpmap:96 mpeg4-generic/8000/1"
                                "a=fmtp: 96 ;profile-level-id=15;mode=AAC-hbr;config=1588;sizeLength=13;indexLength=3;indexDeltaLength=3;profile=1;bitrate=12000"
                                "a=control:1"
                                );
                        
                        
						sprintf(pResponse,
                                "RTSP/1.0 200 OK\r\nServer: RTSP Server\r\nCSeq: %d\r\n"
                                "Date: %s\r\n"
                                "Expires: %s\r\n"
                                "Content-Base: rtsp://%s:%d/livestream/\r\n"
                                "Content-Type: application/sdp\r\n"
                                "x-Accept-Retransmit: our-retransmit\r\n"
                                "x-Accept-Dynamic-Rate: 1\r\n"
                                "Content-Length: %ld\r\n\r\n"
                                "%s",
                                CSeq_no, pCurrentTimeStr, pCurrentTimeStr,
                                pServerIpAddress,vPort,
                                strlen(pSDP), pSDP);
                        break;
                    }
                    case eSetup:
                    {
                        fprintf(stderr, "eDescribe\n");
                        
                        break;
                    }
                    case ePlay:
                    {
                        fprintf(stderr, "ePlay\n");
                        
                        break;
                    }
                        
                    case eTeardown:
                    {
                        fprintf(stderr, "eTeardown\n");
                        
                        break;
                    }
                        
                    default:
                        break;
                }
               
                vSendLen = send(vConnfd, pResponse, strlen(pResponse), 0);
                fprintf(stderr, "vSendLen=%d\n",vSendLen);
                if(vSendLen<0)
                {
                    fprintf(stderr, "send data=%s\n", pResponse);
                }
                
//                vSendLen = sendRTPData( &audio_rtp, pResponse, strlen(pResponse) );
//                fprintf(stderr, "vSendLen=%d\n",vSendLen);
//                if(vSendLen<0)
//                {
//                    fprintf(stderr, "send data=%s\n", pResponse);
//                }

            }
        }
    }
}

