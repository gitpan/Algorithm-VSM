// This code example is from the following source:
//
// Book Title:  Programming with Objects, A Comparative Presentation
//              of Object Oriented Programming with C++ and Java
//
// Chapter:     Chapter 3 ---- The Notion Of A Class And Some Other Ideas
//
// Section:     Section 3.16 - Nested Types
//
// The links to the rest of the code in this book are at
//     
//      http://programming-with-objects.com/pwocode.html
//
// For further information regarding the book, please visit
//
//      http://programming-with-objects.com
//




//InnerClass.java

class X {                           
    private int regularIntEnclosing;                              //(A)
    private static int staticIntEnclosing = 300;                  //(B)

    public class Y{                        
        private int m;
        private int n;
        public Y() { 
            m = regularIntEnclosing;                              //(C)
            n = staticIntEnclosing;                               //(D)
        }
    }

    public X( int n ) { regularIntEnclosing = n; }                //(E) 
}

class Test {
    public static void main( String[] args ) {
        X x = new X( 100 );                                       //(F)
        // X.Y y = new X.Y();             // error
        X.Y y = x.new Y();                // ok                   //(G)
    }
}